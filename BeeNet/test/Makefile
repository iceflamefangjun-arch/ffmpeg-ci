TOPDIR=$(abspath ..)
SOURCES_ROOT=$(abspath ../../..)

ARCH ?= x86_64
BUILD ?= debug

TOOLCHAIN=/data/llvm-mingw-21
PATH:=$(TOOLCHAIN)/bin:$(PATH)
LD_LIBRARY_PATH:=$(TOOLCHAIN)/lib64:$(TOOLCHAIN)/lib:$(LD_LIBRARY_PATH)

AR       = $(TOOLCHAIN)/bin/llvm-ar
RANLIB   = $(TOOLCHAIN)/bin/llvm-ranlib
STRIP    = $(TOOLCHAIN)/bin/llvm-strip
OBJCOPY  = $(TOOLCHAIN)/bin/llvm-objcopy
CC       = $(TOOLCHAIN)/bin/clang-cl
CXX      = $(TOOLCHAIN)/bin/clang-cl
LINK     = $(TOOLCHAIN)/bin/lld-link

TEST_INC_PATH=$(TOPDIR)/test/include
TEST_LIB_PATH=$(TOPDIR)/test/lib/$(BUILD)/$(ARCH)

FFMPEG_DEFS=-DCONFIG_D3D11VA
FFMPEG_LIBS=avformat.lib avcodec.lib avutil.lib swresample.lib swscale.lib fdk-aac.lib

MSVC_INCLUDES = -imsvc $(TOOLCHAIN)/crt/include -imsvc $(TOOLCHAIN)/sdk/include/ucrt -imsvc $(TOOLCHAIN)/sdk/include/um -imsvc $(TOOLCHAIN)/sdk/include/shared
MSVC_LIBS = -libpath:$(TOOLCHAIN)/crt/lib/$(ARCH) -libpath:$(TOOLCHAIN)/sdk/lib/um/$(ARCH) -libpath:$(TOOLCHAIN)/sdk/lib/ucrt/$(ARCH)

ifeq ($(ARCH), x86)
MSVC_BUILD_CFLAGS = --target=i686-pc-windows-msvc -msse3
MSVC_BUILD_LDFLAGS = /machine:x86 /stack:2097152
else ifeq ($(ARCH), x86_64)
MSVC_BUILD_CFLAGS = --target=x86_64-pc-windows-msvc -msse3
MSVC_BUILD_LDFLAGS = /machine:x64 /stack:2097152
else ifeq ($(ARCH), aarch64)
MSVC_BUILD_CFLAGS = --target=aarch64-pc-windows-msvc
MSVC_BUILD_LDFLAGS = /machine:ARM64 /stack:2097152
else
$(error Usage: make ARCH=[x86|x86_64|aarch64] BUILD=[debug|release|static] ...)
endif

OPTIMIZE = -fmerge-all-constants /bigobj /utf-8 /Zc:sizedDealloc- /Zc:twoPhase

ifeq ($(BUILD), debug)
MSVC_BUILD_CFLAGS += /Od /MDd /D_DEBUG $(OPTIMIZE)
MSVC_BUILD_LDFLAGS += /debug
else ifeq ($(BUILD), release)
MSVC_BUILD_CFLAGS += /O2 /MD /DNDEBUG $(OPTIMIZE) /GF /Gy /Gw -flto=thin -fsplit-lto-unit
MSVC_BUILD_CXXFLAGS += -fwhole-program-vtables
else ifeq ($(BUILD), static)
MSVC_BUILD_CFLAGS += /O2 /MT /DNDEBUG $(OPTIMIZE) /GF /Gy /Gw -flto=thin -fsplit-lto-unit
MSVC_BUILD_CXXFLAGS += -fwhole-program-vtables
else
$(error Usage: make ARCH=[x86|x86_64|aarch64] BUILD=[debug|release|static] ...)
endif

CFLAGS   = $(MSVC_BUILD_CFLAGS) -Wno-builtin-macro-redefined
CXXFLAGS = $(MSVC_BUILD_CXXFLAGS) $(CFLAGS) -std:c++17 /EHsc
CPPFLAGS = -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR $(FFMPEG_DEFS) $(MSVC_INCLUDES) -I$(TOPDIR)/include -I$(TEST_INC_PATH)
LDFLAGS  = $(MSVC_BUILD_LDFLAGS) /nologo /subsystem:console $(MSVC_LIBS) -libpath:$(TOPDIR)/lib/$(BUILD)/$(ARCH) -libpath:$(TEST_LIB_PATH)
LIBS     = beenet.lib luacjson.lib luazlib.lib lua.lib curl.lib datachannel.lib \
           cares.lib nghttp2.lib nghttp3.lib ngtcp2.lib ngtcp2_crypto_quictls.lib \
           usrsctp.lib juice.lib ssl.lib crypto.lib zlib.lib xxtea.lib \
           normaliz.lib user32.lib crypt32.lib

SYNC_TEST_BIN  = test1.exe
SYNC_TEST_SRCS = $(abspath sync_test.cpp)
SYNC_TEST_OBJS = $(patsubst $(TOPDIR)/%, .objs/$(BUILD)/$(ARCH)/%, $(patsubst %.cpp, %.o, $(SYNC_TEST_SRCS)))
SYNC_TEST_DEPS = $(patsubst %, %.d, $(SYNC_TEST_OBJS))

ASYNC_TEST_BIN  = test2.exe
ASYNC_TEST_SRCS = $(abspath async_test.cpp)
ASYNC_TEST_OBJS = $(patsubst $(TOPDIR)/%, .objs/$(BUILD)/$(ARCH)/%, $(patsubst %.cpp, %.o, $(ASYNC_TEST_SRCS)))
ASYNC_TEST_DEPS = $(patsubst %, %.d, $(ASYNC_TEST_OBJS))

WS_TEST_BIN  = test3.exe
WS_TEST_SRCS = $(abspath ws_test.cpp)
WS_TEST_OBJS = $(patsubst $(TOPDIR)/%, .objs/$(BUILD)/$(ARCH)/%, $(patsubst %.cpp, %.o, $(WS_TEST_SRCS)))
WS_TEST_DEPS = $(patsubst %, %.d, $(WS_TEST_OBJS))

BEE_PLAYER2_BIN  = bee_player2.exe
BEE_PLAYER2_SRCS = $(abspath bee_player2.cpp BeeAVPlayer.cpp BeeFFmpegUtils.cpp)
BEE_PLAYER2_OBJS = $(patsubst $(TOPDIR)/%, .objs/$(BUILD)/$(ARCH)/%, $(patsubst %.cpp, %.o, $(BEE_PLAYER2_SRCS)))
BEE_PLAYER2_DEPS = $(patsubst %, %.d, $(BEE_PLAYER2_OBJS))

all : $(SYNC_TEST_BIN) $(ASYNC_TEST_BIN) $(WS_TEST_BIN) $(BEE_PLAYER2_BIN)

obj : $(SYNC_TEST_OBJS) $(ASYNC_TEST_OBJS) $(WS_TEST_OBJS) $(BEE_PLAYER2_OBJS)

clean:
	$(RM) -fr .objs $(SYNC_TEST_BIN) $(ASYNC_TEST_BIN) $(WS_TEST_BIN) $(BEE_PLAYER2_BIN)

define make-test
$1 : $2
	$(LINK) $(LDFLAGS) /out:$$@ $$^ $(LIBS) $3
endef

$(eval $(call make-test, $(SYNC_TEST_BIN), $(SYNC_TEST_OBJS)))
$(eval $(call make-test, $(ASYNC_TEST_BIN), $(ASYNC_TEST_OBJS)))
$(eval $(call make-test, $(WS_TEST_BIN), $(WS_TEST_OBJS)))
$(eval $(call make-test, $(BEE_PLAYER2_BIN), $(BEE_PLAYER2_OBJS), $(FFMPEG_LIBS) gdi32.lib dsound.lib dxguid.lib))

.objs/$(BUILD)/$(ARCH)/%.o.d : $(TOPDIR)/%.c
	$(shell mkdir -p $(dir $@))
	$(CC) $(CFLAGS) $(CPPFLAGS) /clang:-MM $< | sed -E 's|$(notdir $*).o[: ]*|.objs/$(ARCH)/$*.o $@: |g' > $@

.objs/$(BUILD)/$(ARCH)/%.o.d : $(TOPDIR)/%.cpp
	$(shell mkdir -p $(dir $@))
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) /clang:-MM $< | sed -E 's|$(notdir $*).o[: ]*|.objs/$(ARCH)/$*.o $@: |g' > $@

.objs/$(BUILD)/$(ARCH)/%.o : $(TOPDIR)/%.c .objs/$(BUILD)/$(ARCH)/%.o.d
	$(shell mkdir -p $(dir $@))
	$(CC) $(CFLAGS) $(CPPFLAGS) -D__FILE__=\"$(basename $(notdir $<))\" -c $< -o $@

.objs/$(BUILD)/$(ARCH)/%.o : $(TOPDIR)/%.cpp .objs/$(BUILD)/$(ARCH)/%.o.d
	$(shell mkdir -p $(dir $@))
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -D__FILE__=\"$(basename $(notdir $<))\" -c $< -o $@

ifeq (, $(filter update clean help, $(MAKECMDGOALS)))
include $(SYNC_TEST_DEPS) $(ASYNC_TEST_DEPS) $(WS_TEST_DEPS) $(BEE_PLAYER2_DEPS)
endif

help:
	@echo "Usage: make ARCH=[x86|x86_64] BUILD=[debug|release|static] ..."
	@echo
	@echo "The following targets are supported:"
	@echo
	@echo " all            (=make) compile and link"
	@echo " obj            just compile, without link"
	@echo " clean          clean target"
	@echo " help           print help information"
	@echo

.PHONY : all obj help clean
