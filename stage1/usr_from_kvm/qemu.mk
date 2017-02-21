$(call setup-stamp-file,QEMU_STAMP)
QEMU_TMPDIR := $(UFK_TMPDIR)/qemu
QEMU_SRCDIR := $(QEMU_TMPDIR)/src
QEMU_BINARY := $(QEMU_SRCDIR)/x86_64-softmmu/qemu-system-x86_64
QEMU_BIOS_BINARIES := bios-256k.bin \
    kvmvapic.bin \
    linuxboot.bin \
    linuxboot_dma.bin \
    vgabios-stdvga.bin \
    efi-virtio.rom

# Disable all possible non-essential features
QEMU_CONFIGURATION_OPTS := \
    --disable-archipelago \
    --disable-bluez \
    --disable-brlapi \
    --disable-bsd-user \
    --disable-bzip2 \
    --disable-cocoa \
    --disable-curl \
    --disable-curses \
    --disable-debug-info \
    --disable-debug-tcg \
    --disable-docs \
    --disable-fdt \
    --disable-glusterfs \
    --disable-gtk \
    --disable-guest-agent \
    --disable-guest-agent-msi \
    --disable-jemalloc \
    --disable-libiscsi \
    --disable-libnfs \
    --disable-libssh2 \
    --disable-libusb \
    --disable-linux-aio \
    --disable-lzo \
    --disable-opengl \
    --disable-qom-cast-debug \
    --disable-rbd \
    --disable-rdma \
    --disable-sdl \
    --disable-seccomp \
    --disable-slirp \
    --disable-smartcard \
    --disable-snappy \
    --disable-spice \
    --disable-strip \
    --disable-tcg-interpreter \
    --disable-tcmalloc \
    --disable-tools \
    --disable-tpm \
    --disable-usb-redir \
    --disable-uuid \
    --disable-vhdx \
    --disable-vnc \
    --disable-vnc-jpeg \
    --disable-vnc-png \
    --disable-vnc-sasl \
    --disable-vte \
    --disable-werror \
    --disable-xen

# only used by QEMU Bridge Helper
QEMU_CONFIGURATION_OPTS += --disable-cap-ng

# default, but be explicit
QEMU_CONFIGURATION_OPTS += --enable-kvm

# required for 9p
QEMU_CONFIGURATION_OPTS += --enable-virtfs

# required for virtfs
QEMU_CONFIGURATION_OPTS += --enable-attr

# required for container networking
QEMU_CONFIGURATION_OPTS += --enable-vhost-net

# specify target build architecture
QEMU_CONFIGURATION_OPTS += --target-list=x86_64-softmmu

# required by qemu to generate content at build time
QEMU_CONFIGURATION_OPTS += --python=/usr/bin/python2

# Ensure the hypervisor is statically-linked
# (required by rkt to simplify binary distribution).
##QEMU_CONFIGURATION_OPTS += --static

QEMU_ACI_BINARY := $(HV_ACIROOTFSDIR)/qemu

# Using 2.7.0 stable release from official repository
QEMU_GIT := https://github.com/01org/qemu-lite.git
QEMU_GIT_COMMIT := qemu-2.7-lite

$(call setup-stamp-file,QEMU_BUILD_STAMP,/build)
$(call setup-stamp-file,QEMU_BIOS_BUILD_STAMP,/bios_build)
$(call setup-stamp-file,QEMU_CONF_STAMP,/conf)
$(call setup-stamp-file,QEMU_DIR_CLEAN_STAMP,/dir-clean)
$(call setup-filelist-file,QEMU_DIR_FILELIST,/dir)
$(call setup-clean-file,QEMU_CLEANMK,/src)

S1_RF_SECONDARY_STAMPS += $(QEMU_STAMP)
S1_RF_INSTALL_FILES += $(QEMU_BINARY):$(QEMU_ACI_BINARY):-
INSTALL_DIRS += \
    $(QEMU_SRCDIR) :- \
    $(QEMU_TMPDIR) :-

# Bios files needs to be removed (source will be removed by QEMU_DIR_CLEAN_STAMP)
CLEAN_FILES += $(foreach bios,$(QEMU_BIOS_BINARIES),$(HV_ACIROOTFSDIR)/${bios})

$(call generate-stamp-rule,$(QEMU_STAMP),$(QEMU_CONF_STAMP) $(QEMU_BUILD_STAMP) $(QEMU_ACI_BINARY) $(QEMU_BIOS_BUILD_STAMP) $(QEMU_DIR_CLEAN_STAMP),,)

$(QEMU_BINARY): $(QEMU_BUILD_STAMP)

$(call generate-stamp-rule,$(QEMU_BIOS_BUILD_STAMP),$(QEMU_CONF_STAMP) $(UFK_CBU_STAMP),, \
	for bios in $(QEMU_BIOS_BINARIES); do \
		$(call vb,vt,COPY BIOS,$$$${bios}) \
		cp $(QEMU_SRCDIR)/pc-bios/$$$${bios} $(HV_ACIROOTFSDIR)/$$$${bios} $(call vl2,>/dev/null); \
	done)

$(call generate-stamp-rule,$(QEMU_BUILD_STAMP),$(QEMU_CONF_STAMP),, \
    $(call vb,vt,BUILD EXT,qemu) \
	$$(MAKE) $(call vl2,--silent) -C "$(QEMU_SRCDIR)" $(call vl2,>/dev/null))

$(call generate-stamp-rule,$(QEMU_CONF_STAMP),,, \
	$(call vb,vt,CONFIG EXT,qemu) \
	cd $(QEMU_SRCDIR); ./configure $(QEMU_CONFIGURATION_OPTS) $(call vl2,>/dev/null))

# Generate filelist of qemu directory (this is both srcdir and
# builddir). Can happen after build finished.
$(QEMU_DIR_FILELIST): $(QEMU_BUILD_STAMP)
$(call generate-deep-filelist,$(QEMU_DIR_FILELIST),$(QEMU_SRCDIR))

# Generate clean.mk cleaning qemu directory
$(call generate-clean-mk,$(QEMU_DIR_CLEAN_STAMP),$(QEMU_CLEANMK),$(QEMU_DIR_FILELIST),$(QEMU_SRCDIR))

GCL_REPOSITORY := $(QEMU_GIT)
GCL_DIRECTORY := $(QEMU_SRCDIR)
GCL_COMMITTISH := $(QEMU_GIT_COMMIT)
GCL_EXPECTED_FILE := Makefile
GCL_TARGET := $(QEMU_CONF_STAMP)
GCL_DO_CHECK :=

include makelib/git.mk

$(call undefine-namespaces,QEMU)
