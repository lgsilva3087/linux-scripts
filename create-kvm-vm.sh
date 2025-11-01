#!/usr/bin/env bash
set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/kvm-vm-create.log"

# Default configuration (can be overridden by environment variables)
VM_NAME="${1:-}"
VM_BASE_DIR="${VM_BASE_DIR:-/mnt/saunafs/VM/kvm}"
IMG_URL="${IMG_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
BASE_IMG="${BASE_IMG:-/var/lib/libvirt/images/ubuntu-24.04-base.img}"
RAM="${RAM:-4096}"
VCPUS="${VCPUS:-4}"
DISK_SIZE="${DISK_SIZE:-32G}"
NETWORK="${NETWORK:-default}"
ENABLE_SSH_KEYS="${ENABLE_SSH_KEYS:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Derived variables
VM_DIR="${VM_BASE_DIR}/${VM_NAME}"
DISK="${VM_DIR}/${VM_NAME}.qcow2"
SEED_ISO="${VM_DIR}/${VM_NAME}-seed.iso"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
        log_info "Cleaning up partial VM creation..."
        if virsh list --all 2>/dev/null | grep -q "^ *$VM_NAME "; then
            log_info "Removing partially created VM: $VM_NAME"
            sudo virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

# Logging functions
log_info() {
    local msg="$1"
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} INFO: $msg" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} WARN: $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ERROR: $msg" | tee -a "$LOG_FILE" >&2
}

# Execute or print commands depending on dry-run mode
run_cmd() {
    local cmd="$*"
    if [ "${DRY_RUN}" = "true" ]; then
        log_info "DRY-RUN: $cmd"
        return 0
    fi
    eval "$cmd"
}

# Usage information
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [VM_NAME] [OPTIONS]

Create a new KVM virtual machine using cloud-init.

ARGUMENTS:
    VM_NAME             Name of the VM to create (required, default: vm-test)

OPTIONS:
    -h, --help          Show this help message
    -r, --ram MB        RAM in MB (default: 4096)
    -c, --cpu CORES     Number of CPU cores (default: 4)
    -s, --size SIZE     Disk size (default: 32G)
    -n, --network NET   Network name (default: default)
    -k, --ssh-keys      Enable SSH key authentication instead of password
    -u, --url URL       Cloud image URL
    -b, --base PATH     Base image path

ENVIRONMENT VARIABLES:
    VM_BASE_DIR         Base directory for VMs (default: /mnt/saunafs/VM/kvm)
    IMG_URL             Ubuntu cloud image URL
    BASE_IMG            Path to base image
    RAM                 RAM in MB
    VCPUS               CPU cores
    DISK_SIZE           Disk size
    NETWORK             Network name
    ENABLE_SSH_KEYS     Enable SSH keys (true/false)

EXAMPLES:
    $SCRIPT_NAME my-vm
    $SCRIPT_NAME my-vm -r 8192 -c 4 -s 50G
    $SCRIPT_NAME my-vm --ssh-keys

EOF
}

# Validation functions
validate_vm_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        log_error "Invalid VM name: $name (must start with alphanumeric, contain only lowercase letters, numbers, dots, underscores, and hyphens)"
        return 1
    fi
}

validate_disk_size() {
    local size="$1"
    if ! [[ "$size" =~ ^[0-9]+[KMGT]$ ]]; then
        log_error "Invalid disk size: $size (use format like 20G, 50G, etc.)"
        return 1
    fi
}

validate_resources() {
    local req_ram=$1
    local available_ram
    available_ram=$(free -m | awk '/^Mem:/{print $7}')

    if [ "$available_ram" -lt "$req_ram" ]; then
        log_warn "Available RAM ($available_ram MB) is less than requested ($req_ram MB)"
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()
    for tool in virsh qemu-img cloud-localds virt-install wget; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install them with: sudo apt-get install -y qemu-kvm libvirt-daemon-system virtinst cloud-image-utils"
        return 1
    fi

    # Check if user can run sudo without password for libvirt commands
    if ! sudo -n true &>/dev/null; then
        log_warn "You may be prompted for your password"
    fi
}

check_vm_exists() {
    if sudo virsh list --all 2>/dev/null | grep -q "^ *$VM_NAME "; then
        log_error "VM '$VM_NAME' already exists"
        log_info "To remove it, run: sudo virsh undefine $VM_NAME --nvram"
        return 1
    fi
}

check_directories() {
    log_info "Checking directories..."

    if ! run_cmd mkdir -p "$VM_DIR"; then
        log_error "Cannot create directory: $VM_DIR"
        return 1
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        log_info "DRY-RUN: Skipping write test in $VM_DIR"
    else
        if ! touch "$VM_DIR/.test" 2>/dev/null; then
            log_error "Cannot write to directory: $VM_DIR"
            rm -f "$VM_DIR/.test"
            return 1
        fi
        rm -f "$VM_DIR/.test"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--ram)
                RAM="$2"
                shift 2
                ;;
            -c|--cpu)
                VCPUS="$2"
                shift 2
                ;;
            -s|--size)
                DISK_SIZE="$2"
                shift 2
                ;;
            -n|--network)
                NETWORK="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -k|--ssh-keys)
                ENABLE_SSH_KEYS="true"
                shift
                ;;
            -u|--url)
                IMG_URL="$2"
                shift 2
                ;;
            -b|--base)
                BASE_IMG="$2"
                shift 2
                ;;
            *)
                if [[ ! "$1" =~ ^- ]]; then
                    VM_NAME="$1"
                    shift
                else
                    log_error "Unknown option: $1"
                    usage
                    exit 1
                fi
                ;;
        esac
    done
}

# Main script starts here
parse_args "$@"

# Validate inputs
if [ -z "$VM_NAME" ]; then
    log_error "VM_NAME is required"
    usage
    exit 1
fi

validate_vm_name "$VM_NAME" || exit 1
validate_disk_size "$DISK_SIZE" || exit 1

log_info "Starting VM creation: $VM_NAME"
log_info "Configuration: RAM=$RAM MB, VCPUS=$VCPUS, DISK_SIZE=$DISK_SIZE, NETWORK=$NETWORK"

check_prerequisites || exit 1
check_vm_exists || exit 1
check_directories || exit 1
validate_resources "$RAM" || true

mkdir -p "$VM_DIR"


# Download base image if needed
if [ ! -f "$BASE_IMG" ]; then
    log_info "Downloading base Ubuntu 24.04 cloud image (this may take a few minutes)..."
    if ! run_cmd sudo wget --progress=dot:mega -O "$BASE_IMG" "$IMG_URL"; then
        log_error "Failed to download base image"
        run_cmd sudo rm -f "$BASE_IMG" || true
        exit 1
    fi
    log_info "Resizing base image to $DISK_SIZE..."
    if ! run_cmd sudo qemu-img resize "$BASE_IMG" "$DISK_SIZE"; then
        log_error "Failed to resize base image"
        exit 1
    fi
else
    log_info "Base image already exists: $BASE_IMG"
fi

# Create VM disk
log_info "Creating VM disk..."
if [ "${DRY_RUN}" = "true" ]; then
    log_info "DRY-RUN: sudo qemu-img create -f qcow2 -b $BASE_IMG -F qcow2 $DISK"
else
    # Use -F to explicitly set backing file format to avoid qemu-img ambiguity
    if ! sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$DISK" 2>>"$LOG_FILE"; then
        log_error "Failed to create VM disk (qemu-img failed). See $LOG_FILE for details."
        log_info "Gathering qemu-img info for debugging..."
        sudo qemu-img info "$BASE_IMG" >>"$LOG_FILE" 2>&1 || true
        sudo qemu-img info "$DISK" >>"$LOG_FILE" 2>&1 || true
        log_error "qemu-img info output written to $LOG_FILE"
        exit 1
    fi
fi

# Generate cloud-init metadata
log_info "Generating cloud-init configuration..."
cat > "${VM_DIR}/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Generate cloud-init user data
if [ "$ENABLE_SSH_KEYS" = "true" ]; then
    log_info "Configuring SSH key authentication..."
    SSH_KEY="${HOME}/.ssh/id_rsa.pub"
    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH public key not found: $SSH_KEY"
        log_info "Generate one with: ssh-keygen -t rsa -b 4096"
        exit 1
    fi
    SSH_KEY_CONTENT=$(cat "$SSH_KEY")
    cat > "${VM_DIR}/user-data" <<EOF
#cloud-config
ssh_pwauth: false
ssh_authorized_keys:
  - $SSH_KEY_CONTENT
packages:
  - qemu-guest-agent
EOF
else
    cat > "${VM_DIR}/user-data" <<EOF
#cloud-config
ssh_pwauth: true
password: ubuntu
chpasswd:
  expire: false
packages:
  - qemu-guest-agent
EOF
fi

# Create seed ISO
log_info "Creating cloud-init seed ISO..."
if ! run_cmd sudo cloud-localds "$SEED_ISO" "${VM_DIR}/user-data" "${VM_DIR}/meta-data"; then
    log_error "Failed to create seed ISO"
    exit 1
fi

# Create VM with virt-install
log_info "Creating VM with virt-install..."
VIRT_CMD=(sudo virt-install --name "$VM_NAME" --memory "$RAM" --vcpus "$VCPUS" --disk "path=$DISK,format=qcow2" --disk "path=$SEED_ISO,device=cdrom" --os-variant ubuntu24.04 --network "network=$NETWORK" --graphics none --import --noautoconsole)
if [ "${DRY_RUN}" = "true" ]; then
    log_info "DRY-RUN: ${VIRT_CMD[*]}"
else
    if ! "${VIRT_CMD[@]}"; then
        log_error "Failed to create VM"
        exit 1
    fi
fi

log_info "✓ VM '$VM_NAME' created successfully!"
log_info "Configuration saved in: $VM_DIR"
log_info ""
log_info "Next steps:"
log_info "  - Check VM status:   virsh list --all"
log_info "  - Connect to VM:     virsh console $VM_NAME"
log_info "  - Get VM info:       virsh dominfo $VM_NAME"
if [ "$ENABLE_SSH_KEYS" = "true" ]; then
    log_info "  - SSH to VM:         ssh ubuntu@<vm-ip>"
else
    log_info "  - SSH to VM:         ssh ubuntu@<vm-ip> (password: ubuntu)"
fi
log_info ""
