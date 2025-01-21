#!/usr/libexec/flua
--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

local preamble = {}

str = [[/*
 *  BSD syscalls
 *
 *  Copyright (c) 2003-2008 Fabrice Bellard
 *  Copyright (c) 2013-2014 Stacey D. Son
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, see <http://www.gnu.org/licenses/>.
 */
#define _ACL_PRIVATE 1	// XXX Don't upstream: we need to sort out this junk and the twisty maze of .h

#include "qemu/osdep.h"

#include "qemu/cutils.h"
#include "qemu/path.h"
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <poll.h>

#include "include/gdbstub/syscalls.h"

#include "qemu.h"
#include "signal-common.h"
#include "user/syscall-trace.h"
#include "truss_hdr.h"
#include "systruss.h"

/* BSD independent syscall shims */
#include "bsd-file.h"
#include "bsd-ioctl.h"
#include "bsd-mem.h"
#include "bsd-misc.h"
#include "bsd-proc.h"
#include "bsd-signal.h"
#include "bsd-socket.h"

/* *BSD dependent syscall shims */
#include "os-extattr.h"
#include "os-file.h"
#include "os-time.h"
#include "os-misc.h"
#include "os-proc.h"
#include "os-signal.h"
#include "os-socket.h"
#include "os-stat.h"
#include "os-thread.h"

/* Used in os-thread */
safe_syscall1(int, thr_suspend, struct timespec *, timeout);
safe_syscall5(int, _umtx_op, void *, obj, int, op, unsigned long, val, void *,
    uaddr, void *, uaddr2);

/* used in os-time */
safe_syscall2(int, nanosleep, const struct timespec *, rqtp, struct timespec *,
    rmtp);
safe_syscall4(int, clock_nanosleep, clockid_t, clock_id, int, flags,
    const struct timespec *, rqtp, struct timespec *, rmtp);

safe_syscall6(int, kevent, int, kq, const struct kevent *, changelist,
    int, nchanges, struct kevent *, eventlist, int, nevents,
    const struct timespec *, timeout);

/* BSD dependent syscall shims */
#include "os-stat.h"
#include "os-proc.h"
#include "os-misc.h"

/* I/O */
safe_syscall3(int, open, const char *, path, int, flags, mode_t, mode);
safe_syscall4(int, openat, int, fd, const char *, path, int, flags, mode_t,
    mode);

safe_syscall3(ssize_t, read, int, fd, void *, buf, size_t, nbytes);
safe_syscall4(ssize_t, pread, int, fd, void *, buf, size_t, nbytes, off_t,
    offset);
safe_syscall3(ssize_t, readv, int, fd, const struct iovec *, iov, int, iovcnt);
safe_syscall4(ssize_t, preadv, int, fd, const struct iovec *, iov, int, iovcnt,
    off_t, offset);

safe_syscall3(ssize_t, write, int, fd, void *, buf, size_t, nbytes);
safe_syscall4(ssize_t, pwrite, int, fd, void *, buf, size_t, nbytes, off_t,
    offset);
safe_syscall3(ssize_t, writev, int, fd, const struct iovec *, iov, int, iovcnt);
safe_syscall4(ssize_t, pwritev, int, fd, const struct iovec *, iov, int, iovcnt,
    off_t, offset);

safe_syscall5(int, select, int, nfds, fd_set *, readfs, fd_set *, writefds,
    fd_set *, exceptfds, struct timeval *, timeout);
safe_syscall6(int, pselect, int, nfds, fd_set * restrict, readfs,
    fd_set * restrict, writefds, fd_set * restrict, exceptfds,
    const struct timespec * restrict, timeout,
    const sigset_t * restrict, newsigmask);

safe_syscall6(ssize_t, recvfrom, int, fd, void *, buf, size_t, len, int, flags,
    struct sockaddr * restrict, from, socklen_t * restrict, fromlen);
safe_syscall6(ssize_t, sendto, int, fd, const void *, buf, size_t, len, int,
    flags, const struct sockaddr *, to, socklen_t, tolen);
safe_syscall3(ssize_t, recvmsg, int, s, struct msghdr *, msg, int, flags);
safe_syscall3(ssize_t, sendmsg, int, s, const struct msghdr *, msg, int, flags);

safe_syscall4(int, ppoll, struct pollfd *, fds, nfds_t, nfds,
              const struct timespec * restrict, timeout,
              const sigset_t * restrict, newsigmask);

#if defined(__FreeBSD_version) && __FreeBSD_version >= 1300133
safe_syscall6(ssize_t, copy_file_range, int, infd, off_t *, inoffp, int, outfd,
    off_t *, outoffp, size_t, len, unsigned int, flags);
#endif

int g_posix_timers[32] = { 0, } ;

/* used in os-proc */
safe_syscall4(pid_t, wait4, pid_t, wpid, int *, status, int, options,
    struct rusage *, rusage);
safe_syscall6(pid_t, wait6, idtype_t, idtype, id_t, id, int *, status, int,
    options, struct __wrusage *, wrusage, siginfo_t *, infop);

/*
 * errno conversion.
 */
abi_long get_errno(abi_long ret)
{
    if (ret == -1) {
        return -host_to_target_errno(errno);
    } else {
        return ret;
    }
}

int host_to_target_errno(int err)
{
    /*
     * All the BSDs have the property that the error numbers are uniform across
     * all architectures for a given BSD, though they may vary between different
     * BSDs.
     */
    return err;
}

bool is_error(abi_long ret)
{
    return (abi_ulong)ret >= (abi_ulong)(-4096);
}

/*
 * Unlocks a iovec. Unlike unlock_iovec, it assumes the tvec array itself is
 * already locked from target_addr. It will be unlocked as well as all the iovec
 * elements.
 */
static void helper_unlock_iovec(struct target_iovec *target_vec,
                                abi_ulong target_addr, struct iovec *vec,
                                int count, int copy)
{
    for (int i = 0; i < count; i++) {
        abi_ulong base = tswapal(target_vec[i].iov_base);

        if (vec[i].iov_base) {
            unlock_user(vec[i].iov_base, base, copy ? vec[i].iov_len : 0);
        }
    }
    unlock_user(target_vec, target_addr, 0);
}

struct iovec *lock_iovec(int type, abi_ulong target_addr,
        int count, int copy)
{
    struct target_iovec *target_vec;
    struct iovec *vec;
    abi_ulong total_len, max_len;
    int i;
    int err = 0;

    if (count == 0) {
        errno = 0;
        return NULL;
    }
    if (count < 0 || count > IOV_MAX) {
        errno = EINVAL;
        return NULL;
    }

    vec = g_try_new0(struct iovec, count);
    if (vec == NULL) {
        errno = ENOMEM;
        return NULL;
    }

    target_vec = lock_user(VERIFY_READ, target_addr,
                           count * sizeof(struct target_iovec), 1);
    if (target_vec == NULL) {
        err = EFAULT;
        goto fail2;
    }

    max_len = 0x7fffffff & MIN(TARGET_PAGE_MASK, PAGE_MASK);
    total_len = 0;

    for (i = 0; i < count; i++) {
        abi_ulong base = tswapal(target_vec[i].iov_base);
        abi_long len = tswapal(target_vec[i].iov_len);

        if (len < 0) {
            err = EINVAL;
            goto fail;
        } else if (len == 0) {
            /* Zero length pointer is ignored. */
            vec[i].iov_base = 0;
        } else {
            vec[i].iov_base = lock_user(type, base, len, copy);
            /*
             * If the first buffer pointer is bad, this is a fault.  But
             * subsequent bad buffers will result in a partial write; this is
             * realized by filling the vector with null pointers and zero
             * lengths.
             */
            if (!vec[i].iov_base) {
                if (i == 0) {
                    err = EFAULT;
                    goto fail;
                } else {
                    /*
                     * Fail all the subsequent addresses, they are already
                     * zero'd.
                     */
                    goto out;
                }
            }
            if (len > max_len - total_len) {
                len = max_len - total_len;
            }
        }
        vec[i].iov_len = len;
        total_len += len;
    }
out:
    unlock_user(target_vec, target_addr, 0);
    return vec;

fail:
    helper_unlock_iovec(target_vec, target_addr, vec, i, copy);
fail2:
    g_free(vec);
    errno = err;
    return NULL;
}

void unlock_iovec(struct iovec *vec, abi_ulong target_addr,
        int count, int copy)
{
    struct target_iovec *target_vec;

    target_vec = lock_user(VERIFY_READ, target_addr,
                           count * sizeof(struct target_iovec), 1);
    if (target_vec) {
        helper_unlock_iovec(target_vec, target_addr, vec, count, copy);
    }

    g_free(vec);
}
]]

return preamble
