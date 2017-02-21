// Copyright 2016 The rkt Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package hvqemu

import (
	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/coreos/rkt/stage1/init/kvm"
	"github.com/coreos/rkt/stage1/init/kvm/hypervisor"
)

// roundUpToMultiple rounds the specified number up to the nearest
// provided multiple.
//
// For example, specifying (num=9, multiple=8) returns 16.
func roundUpToMultiple(num, multiple int64) int64 {
	return (num + (multiple - 1)) & ^(multiple - 1)
}

// StartCmd takes path to stage1, name of the machine, path to kernel, network describers, memory in megabytes
// and quantity of cpus and prepares command line to run QEMU process
func StartCmd(wdPath, name, kernelPath string, nds []kvm.NetDescriber, cpu, mem int64, debug bool) []string {
	var (
		driverConfiguration = hypervisor.KvmHypervisor{
			Bin: "./qemu",
			KernelParams: []string{
				"root=/dev/root",
				"rootfstype=9p",
				"rootflags=trans=virtio,version=9p2000.L,cache=mmap",
				"rw",
				"systemd.default_standard_error=journal+console",
				"systemd.default_standard_output=journal+console",
				"tsc=reliable",
				"no_timer_check",
				"rcupdate.rcu_expedited=1",
				"i8042.direct=1",
				"i8042.dumbkbd=1",
				"i8042.nopnp=1",
				"i8042.noaux=1",
				"noreplace-smp",
				"reboot=k",
				"panic=1",
				"console=hvc0",
				"console=hvc1",
				"initcall_debug",
				"iommu=off",
				"quiet",
				"cryptomgr.notests",
			},
		}
	)

	driverConfiguration.InitKernelParams(debug)

	cpuStr := strconv.FormatInt(cpu, 10)

	// Allow one extra GiB of memory
	// (qemu requires maxmem to be rounded on a 4k boundary)

	gib := int64(1024 * 1024 * 1024)
	maxMem := roundUpToMultiple(mem+gib, int64(4096))
	maxMemStr := strconv.FormatInt(maxMem, 10)

	cmd := []string{
		filepath.Join(wdPath, driverConfiguration.Bin),
		"-L", wdPath,
		"-no-reboot",
		"-vga", "none",
		"-nographic",
		"-enable-kvm",

		// Minimise overhead; the kernel does not perform
		// well with multi-socket qemu.
		"-smp", fmt.Sprintf("%s,sockets=1,cores=%s,threads=1", cpuStr, cpuStr),

		// Slots is set to two since:
		//
		// - slot 1 represents normal memory.
		// - slot 2 represents NVDIMM.
		//
		// XXX: maxmem must be larger than the sum of normal memory and nvdimm.
		"-m", fmt.Sprintf("%s,slots=2,maxmem=%s", strconv.FormatInt(mem, 10), maxMemStr),

		"-kernel", kernelPath,
		"-fsdev", "local,id=root,path=stage1/rootfs,security_model=none",
		"-device", "virtio-9p-pci,fsdev=root,mount_tag=/dev/root",
		"-append", fmt.Sprintf("%s", strings.Join(driverConfiguration.KernelParams, " ")),
		"-chardev", "stdio,id=virtiocon0,signal=off",
		"-device", "virtio-serial",
		"-device", "virtconsole,chardev=virtiocon0",
		"-machine", "pc-lite,accel=kvm,kernel_irqchip,nvdimm",
		"-cpu", "host",
		"-rtc", "base=utc,driftfix=slew",
		"-no-user-config",
		"-nodefaults",
		"-global", "kvm-pit.lost_tick_policy=discard",
	}

	return append(cmd, kvmNetArgs(nds)...)
}

// kvmNetArgs returns additional arguments that need to be passed
// to qemu to configure networks properly. Logic is based on
// network configuration extracted from Networking struct
// and essentially from activeNets that expose NetDescriber behavior
func kvmNetArgs(nds []kvm.NetDescriber) []string {
	var qemuArgs []string

	for _, nd := range nds {
		qemuArgs = append(qemuArgs, []string{"-device", "driver=virtio-net-pci,netdev=testnet0"}...)
		qemuNic := fmt.Sprintf("tap,id=testnet0,ifname=%s,script=no,downscript=no,vhost=on", nd.IfName())
		qemuArgs = append(qemuArgs, []string{"-netdev", qemuNic}...)
	}

	return qemuArgs
}
