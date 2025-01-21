# From /Makefile.inc1

# We can't assume here that ${TMPPATH} will include ${PATH} or /usr/libexec
# because we may be building with a STRICTTMPPATH, so we explicitly include
# /usr/libexec here for flua.  ${TMPPATH} still usefully includes anything else
# we may need to function.
_sysent_PATH=	${TMPPATH}:/usr/libexec
_sysent_dirs=	sys/kern
_sysent_dirs+=	sys/compat/freebsd32
_sysent_dirs+=	sys/amd64/linux		\
		sys/amd64/linux32	\
		sys/arm64/linux		\
		sys/i386/linux

sysent: .PHONY
.for _dir in ${_sysent_dirs}
sysent-${_dir}: .PHONY
	@echo "${MAKE} -C ${.CURDIR}/${_dir} sysent"
	${_+_}@env PATH=${_sysent_PATH:Q} ${MAKE} -C ${.CURDIR}/${_dir} sysent

sysent: sysent-${_dir}
.endfor
