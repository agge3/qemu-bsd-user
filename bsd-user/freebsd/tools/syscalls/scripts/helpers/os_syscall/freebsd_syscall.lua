#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

--
-- `freebsd_syscall` is a helper of `os_syscall.lua`. It auto-generates the
-- correct buffer for the function `freebsd_syscall`, to be used by the larger
-- generator `os_syscall.lua` to generate `os-syscall.c`.

local config = require("config")
local scarg = require("core.scarg")
local scret = require("core.scret")
local util = require("tools.util")

local freebsd_syscall = {}

freebsd_syscall.__index = freebsd_syscall

local function addDecl()
	self.buf = [[/*
 * All errnos that freebsd_syscall() returns must be -TARGET_<errcode>.
 */
static abi_long freebsd_syscall(void *cpu_env, int num, abi_long arg1,
                                abi_long arg2, abi_long arg3, abi_long arg4,
                                abi_long arg5, abi_long arg6, abi_long arg7,
                                abi_long arg8)
{
	abi_long ret;

	switch (num) {
		/*
		 * process system calls
		 */]]
end

local function addDef()
	-- Grab the master system calls table.
	local s = tbl.syscalls

	for _, v in pairs(s) do
		args = ""

		-- Add `cpu_env` if needed for this system call.
		-- xxx under what condition?

		-- Add correct amount of arguments for this system call.
		for i = 1, #v.args do
			-- xxx think through better/test
			if args ~= "" and #v.args > 1 then
				args = args + ", arg" + i
			else
				args = "arg1"
			end

		-- Will always be section two of the man pages, it's a system call.
		self.buf = self.buf + string.format([[
	case TARGET_FREEBSD_NR_%s: /* %s(2) */
		ret = do_freebsd_%s(%s);
		break;
]]), v.name, v.name, v.name, args)

		-- xxx need to handle compat minor version? that can possibly be
		-- obtained ...somewhere
		
		-- xxx there's groupings, like "time, signal, socket".
		-- some of those can easily be obtained in the syscall name, others 
		-- might be more difficult. how important?
		
		-- XXX special conditions:
--#if defined(CONFIG_GETRANDOM)
--    case TARGET_FREEBSD_NR_getrandom:
--        ret = do_freebsd_getrandom(arg1, arg2, arg3);
--        break;
--#endif
--
--#ifdef TARGET_FREEBSD_NR_sstk
--    case TARGET_FREEBSD_NR_sstk:
--        ret = do_bsd_sstk();
--        break;
--#endif
--
--#ifdef TARGET_FREEBSD_NR_sbrk
--    case TARGET_FREEBSD_NR_sbrk:
--        ret = do_bsd_sbrk();
--        break;
--#endif
--
--#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300048
--    case TARGET_FREEBSD_NR_shm_open2: /* shm_open2(2) */
--        ret = do_freebsd_shm_open2(arg1, arg2, arg3, arg4, arg5);
--        break;
--#endif
--
--#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300049
--    case TARGET_FREEBSD_NR_shm_rename: /* shm_rename(2) */
--        ret = do_freebsd_shm_rename(arg1, arg2, arg3);
--        break;
--#endif
--
--#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300080
--    case TARGET_FREEBSD_NR___realpathat:
--        /* __realpathat(2) (XXX no realpathat()) */
--        ret = do_freebsd_realpathat(arg1, arg2, arg3, arg4, arg5);
--        break;
--#endif
--
--#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300037
--    case TARGET_FREEBSD_NR_copy_file_range:
--        ret = do_freebsd_copy_file_range(arg1, arg2, arg3, arg4, arg5, arg6);
--        break;
--#endif
--
--#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300133
--    case TARGET_FREEBSD_NR___specialfd:
--        ret = do_freebsd___specialfd(arg1, arg2, arg3);
--        break;
--#endif
--
--#if TARGET_FREEBSD_NR_freebsd13_swapoff
--    case TARGET_FREEBSD_NR_freebsd13_swapoff: /* freebsd13_swapoff(2) */
--        ret = do_freebsd13_swapoff(arg1);
--        break;
--#endif
--
--#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300091
--    case TARGET_FREEBSD_NR_close_range: /* close_range(2) */
--        ret = do_freebsd_close_range(arg1, arg2, arg3);
--        break;
--#endif

-- all of this:
--	/* XXX */
--    case TARGET_FREEBSD_NR_cap_rights_limit:
--    case TARGET_FREEBSD_NR_cap_ioctls_limit:
--    case TARGET_FREEBSD_NR_cap_fcntls_limit:
--	ret = EINVAL;
--	break;
--    case TARGET_FREEBSD_NR_cap_enter:
--	ret = 0;
--	break;
--
--    default:
--    {
--        const char *name;
--
--        name = decoded_syscalls[num].name;
--        if (name == NULL) {
--            /* _mask(LOG_UNIMP, maybe? */
--            qemu_log("Unsupported syscall #%d\n", num);
--        } else {
--            /* _mask(LOG_UNIMP, maybe? */
--            qemu_log("Unsupported syscall %s()\n", name);
--        }
--#if 0
--        ret = get_errno(syscall(num, arg1, arg2, arg3, arg4, arg5, arg6, arg7,
--                    arg8));
--#endif
--        ret = -TARGET_ENOSYS;
--        break;
--            }
--    }
--
--    return ret;
--}
		










end

function freebsd_syscall:new(obj)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self

	self.buf = ""

	return obj
end

return freebsd_syscall
