# plasma

# (copied/modified from https://github.com/gstrauss/mcdb/blob/master/Makefile)

ifneq (,$(wildcard /bin/uname))
OSNAME:=$(shell /bin/uname -s)
else
OSNAME:=$(shell /usr/bin/uname -s)
endif

.PHONY: all
all: libplasma.a libplasma.so

PREFIX?=/usr/local
ifneq (,$(PREFIX))
PREFIX_USR?=$(PREFIX)
else
PREFIX_USR?=/usr
endif

ifneq (,$(RPM_ARCH))
ifeq (x86_64,$(RPM_ARCH))
  ABI_BITS=64
  LIB_BITS=64
endif
else
ifneq (,$(wildcard /lib64))
  ABI_BITS=64
  LIB_BITS=64
endif
endif

# 'gmake ABI_BITS=64' for 64-bit build (recommended on all 64-bit platforms)
ifeq (64,$(ABI_BITS))
ifeq ($(OSNAME),Linux)
ABI_FLAGS?=-m64
endif
ifeq ($(OSNAME),Darwin)
ABI_FLAGS?=-m64
endif
ifeq ($(OSNAME),AIX)
AR+=-X64
ABI_FLAGS?=-maix64
endif
ifeq ($(OSNAME),HP-UX)
ABI_FLAGS?=-mlp64
endif
ifeq ($(OSNAME),SunOS)
ABI_FLAGS?=-m64
endif
endif

# (plasma_atomic requires 64-bit POWER CPU for 8-byte atomics in 32-bit build)
# (gcc -mcpu=power5 results in _ARCH_PWR5 being defined)
ifeq ($(OSNAME),AIX)
ifneq (64,$(ABI_BITS))
ABI_FLAGS?=-maix32 -mcpu=power5
endif
endif
# XXX: Linux (not AIX) on POWER needs gcc -m32 -mpowerpc64 for 8-byte atomics
# in 32-bit builds, or gcc 4.8.1 with libatomic (or gcc 4.7 with end-user
# downloading and compiling libatomic) and linking with -latomic

ifeq (32,$(ABI_BITS))
ifeq ($(OSNAME),Linux)
ABI_FLAGS?=-m32
endif
ifeq ($(OSNAME),Darwin)
ABI_FLAGS?=-m32
endif
ifeq ($(OSNAME),AIX)
AR+=-X32
ABI_FLAGS?=-maix32
endif
ifeq ($(OSNAME),HP-UX)
ABI_FLAGS?=-milp32
endif
ifeq ($(OSNAME),SunOS)
ABI_FLAGS?=-m32
endif
endif

# cygwin needs -std=gnu99 or -D_GNU_SOURCE for mkstemp() and strerror_r()
# cygwin gcc does not support -fpic or -pthread
ifneq (,$(filter CYGWIN%,$(OSNAME)))
FPIC=
STDC99=-std=gnu99
PTHREAD_FLAGS=-D_THREAD_SAFE
endif

ifneq (,$(RPM_OPT_FLAGS))
  CFLAGS+=$(RPM_OPT_FLAGS)
  LDFLAGS+=$(RPM_OPT_FLAGS)
else
  CC=gcc -pipe
  ANSI?=-ansi
  WARNING_FLAGS?=-Wall -Winline -pedantic $(ANSI)
  CFLAGS+=$(WARNING_FLAGS) -O3 -g $(ABI_FLAGS)
  LDFLAGS+=$(ABI_FLAGS)
  ifneq (,$(filter %clang,$(CC)))
    ANSI=
  endif
endif
 
# To disable uint32 C99 inline functions:
#   -DNO_C99INLINE
# Another option to smaller binary is -Os instead of -O3, and remove -Winline

ifeq ($(OSNAME),Linux)
  ifneq (,$(strip $(filter-out /usr,$(PREFIX))))
    RPATH= -Wl,-rpath,$(PREFIX)/lib$(LIB_BITS)
  endif
  ifeq (,$(RPM_OPT_FLAGS))
    CFLAGS+=-D_FORTIFY_SOURCE=2 -fstack-protector
  endif
  # earlier versions of GNU ld might not support -Wl,--hash-style,gnu
  # (safe to remove -Wl,--hash-style,gnu for RedHat Enterprise 4)
  LDFLAGS+=-Wl,-O,1 -Wl,--hash-style,gnu -Wl,-z,relro,-z,now
  # Linux on POWER CPU with gcc < 4.7 and 32-bit compilation requires
  # modification to Makefile to replace instances of -m32 with -m32 -mpowerpc64
  # for plasma_atomic.h support for atomic operations on 8-byte entities
endif
ifeq ($(OSNAME),Darwin)
  # clang 3.1 compiler supports __thread and TLS; gcc 4.2.1 does not
  CC=clang -pipe
  ifneq (,$(filter %clang,$(CC)))
    ANSI=
  endif
  ifneq (,$(strip $(filter-out /usr,$(PREFIX))))
    RPATH= -Wl,-rpath,$(PREFIX)/lib$(LIB_BITS)
  endif
  ifeq (,$(RPM_OPT_FLAGS))
    CFLAGS+=-D_FORTIFY_SOURCE=2 -fstack-protector
  endif
endif
ifeq ($(OSNAME),AIX)
  ifneq (,$(strip $(filter-out /usr,$(PREFIX))))
    RPATH= -Wl,-b,libpath:$(PREFIX)/lib$(LIB_BITS)
  endif
  # -lpthreads (AIX) for pthread_mutex_{lock,unlock}()
  libplasma.so: LDFLAGS+=-lpthreads
endif
ifeq ($(OSNAME),HP-UX)
  ifneq (,$(strip $(filter-out /usr,$(PREFIX))))
    RPATH= -Wl,+b,$(PREFIX)/lib$(LIB_BITS)
  endif
endif
ifeq ($(OSNAME),SunOS)
  ifneq (,$(strip $(filter-out /usr,$(PREFIX))))
    RPATH= -Wl,-R,$(PREFIX)/lib$(LIB_BITS)
  endif
  CFLAGS+=-D_POSIX_PTHREAD_SEMANTICS
  # -lrt for sched_yield()
  libplasma.so: LDFLAGS+=-lrt
endif

# heavy handed dependencies
_DEPENDENCIES_ON_ALL_HEADERS_Makefile:= $(wildcard *.h) Makefile

# C99 and POSIX.1-2001 (SUSv3 _XOPEN_SOURCE=600)
# C99 and POSIX.1-2008 (SUSv4 _XOPEN_SOURCE=700)
STDC99?=-std=c99
POSIX_STD?=-D_XOPEN_SOURCE=600
CFLAGS+=$(STDC99) $(POSIX_STD)
# position independent code (for shared libraries)
FPIC?=-fpic
# link shared library
SHLIB?=-shared

# Thread-safety (e.g. for thread-specific errno)
# (vendor compilers might need additional compiler flags, e.g. Sun Studio -mt)
PTHREAD_FLAGS?=-pthread -D_THREAD_SAFE
CFLAGS+=$(PTHREAD_FLAGS)

# To use vendor compiler, set CC and the following macros, as appropriate:
#   Oracle Sun Studio
#     CC=cc
#     STDC99=-xc99=all
#     PTHREAD_FLAGS=-mt -D_THREAD_SAFE
#     FPIC=-xcode=pic13
#     SHLIB=-G
#     WARNING_FLAGS=-v
#     CFLAGS+=-fast -xbuiltin
#   IBM Visual Age XL C/C++
#     CC=xlc
#     # use -qsuppress to silence msg: keyword '__attribute__' is non-portable
#     STDC99=-qlanglvl=stdc99 -qsuppress=1506-1108
#     PTHREAD_FLAGS=-qthreaded -D__VACPP_MULTI__ -D_THREAD_SAFE
#     FPIC=-qpic=small
#     SHLIB=-qmkshrobj
#     WARNING_FLAGS=
#     CFLAGS+=-qnoignerrno
#     #(64-bit)
#     ABI_FLAGS=-q64
#   HP aCC
#     CC=cc
#     STDC99=-AC99
#     PTHREAD_FLAGS=-mt -D_THREAD_SAFE
#     FPIC=+z
#     SHLIB=-b
#     #(noisy; quiet informational messages about adding padding to structs)
#     WARNING_FLAGS=+w +W4227,4255
#     #(64-bit)
#     ABI_FLAGS=+DD64
#     #(additionally, aCC does not appear to support C99 inline)
#     CFLAGS+=-DNO_C99INLINE

%.o: %.c $(_DEPENDENCIES_ON_ALL_HEADERS_Makefile)
	$(CC) -o $@ $(CFLAGS) -c $<

PLASMA_OBJS:= plasma_atomic.o plasma_attr.o \
              plasma_endian.o plasma_spin.o plasma_sysconf.o plasma_test.o

PIC_OBJS:= $(PLASMA_OBJS)
$(PIC_OBJS): CFLAGS+=$(FPIC)

ifeq ($(OSNAME),Linux)
libplasma.so: LDFLAGS+=-Wl,-soname,$(@F)
endif
libplasma.so: $(PLASMA_OBJS)
	$(CC) -o $@ $(SHLIB) $(FPIC) $(LDFLAGS) $^

libplasma.a: $(PLASMA_OBJS)
	$(AR) -r $@ $^

$(PREFIX)/lib:
	/bin/mkdir -p -m 0755 $@
ifneq (,$(LIB_BITS))
$(PREFIX)/lib$(LIB_BITS):
	/bin/mkdir -p -m 0755 $@
endif
ifneq ($(PREFIX_USR),$(PREFIX))
$(PREFIX_USR)/lib:
	/bin/mkdir -p -m 0755 $@
ifneq (,$(LIB_BITS))
$(PREFIX_USR)/lib$(LIB_BITS):
	/bin/mkdir -p -m 0755 $@
endif
endif

# (update library atomically (important to avoid crashing running programs))
# (could use /usr/bin/install if available)
$(PREFIX_USR)/lib$(LIB_BITS)/libplasma.so: libplasma.so \
                                           $(PREFIX_USR)/lib$(LIB_BITS)
	/bin/cp -f $< $@.$$$$ \
	&& /bin/mv -f $@.$$$$ $@

.PHONY: install-headers install install-doc install-plasma-headers
install-plasma-headers: plasma/plasma_atomic.h \
                        plasma/plasma_attr.h \
                        plasma/plasma_endian.h \
                        plasma/plasma_feature.h \
                        plasma/plasma_ident.h \
                        plasma/plasma_membar.h \
                        plasma/plasma_spin.h \
                        plasma/plasma_stdtypes.h \
                        plasma/plasma_sysconf.h \
                        plasma/plasma_test.h
	/bin/mkdir -p -m 0755 $(PREFIX_USR)/include/plasma
	umask 333; \
	  /bin/cp -f --preserve=timestamps $^ $(PREFIX_USR)/include/plasma/
install-headers: install-plasma-headers
install-doc: COPYING CREDITS README
	/bin/mkdir -p -m 0755 $(PREFIX_USR)/share/doc/plasma
	umask 333; \
	  /bin/cp -f --preserve=timestamps $^ $(PREFIX_USR)/share/doc/plasma/
install: $(PREFIX_USR)/lib$(LIB_BITS)/libplasma.so \
         install-headers


usr_bin_id:=$(wildcard /usr/xpg4/bin/id)
ifeq (,$(usr_bin_id))
usr_bin_id:=/usr/bin/id
endif

.PHONY: clean realclean
clean:
	[ "$$($(usr_bin_id) -u)" != "0" ]
	$(RM) libplasma.a libplasma.so *.o

realclean: clean
