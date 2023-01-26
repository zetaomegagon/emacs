# Copyright 2023 Free Software Foundation, Inc.

# This file is part of GNU Emacs.

# GNU Emacs is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# GNU Emacs is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

# ndk-build works by including a bunch of Makefiles which set
# variables, and then having those Makefiles include another makefile
# which actually builds targets.

eq = $(and $(findstring $(1),$(2)),$(findstring $(2),$(1)))
objname = $(1)-$(subst /,_,$(2).o)

# Here are the default flags to link shared libraries with.
NDK_SO_DEFAULT_LDFLAGS := -lc -lm

define single-object-target

ifeq (x$(suffix $(1)),x.c)

$(call objname,$(LOCAL_MODULE),$(basename $(1))): $(LOCAL_PATH)/$(1)
	$(NDK_BUILD_CC) -c $$< -o $$@ $(NDK_CFLAGS_$(LOCAL_MODULE))

else
ifeq (x$(suffix $(1)),x.$(or $(LOCAL_CPP_EXTENSION),cpp))

$(call objname,$(LOCAL_MODULE),$(basename $(1))): $(LOCAL_PATH)/$(1)
	$(NDK_BUILD_CC) -c $$< -o $$@ $(NDK_CFLAGS_$(LOCAL_MODULE)) $(NDK_CXXFLAGS_$(LOCAL_MODULE))

else
ifneq ($(or $(call eq,x$(suffix $(1)),x.s),$(call eq,x$(suffix $(1)),x.S)),)

$(call objname,$(LOCAL_MODULE),$(basename $(1))): $(LOCAL_PATH)/$(1)
	$(NDK_BUILD_CC) -c $$< -o $$@ $(NDK_ASFLAGS_$(LOCAL_MODULE))

else
ifneq (x$(suffix $(1)),x.asm)
$$(error Unsupported suffix: $(suffix $(1)))
else
ifeq ($(findstring x86,$(NDK_BUILD_ARCH)),)
$$(error Trying to build nasm file on non-Intel platform!)
else

$(call objname,$(LOCAL_MODULE),$(basename $(1))): $(LOCAL_PATH)/$(1)
	$(NDK_BUILD_NASM) -o $$@ -i $(LOCAL_PATH) -i $$(dir $$<) $(NDK_ASFLAGS_$(LOCAL_MODULE)) $$<

endif
endif
endif
endif
endif

ALL_OBJECT_FILES$(LOCAL_MODULE) += $(call objname,$(LOCAL_MODULE),$(basename $(1)))

endef

# Make sure to not add a prefix to local includes that already specify
# $(LOCAL_PATH).
NDK_CFLAGS_$(LOCAL_MODULE)	 := $(addprefix -I,$(LOCAL_C_INCLUDES))
NDK_CFLAGS_$(LOCAL_MODULE)	 += -fPIC -iquote $(LOCAL_PATH) $(LOCAL_EXPORT_CFLAGS) $(LOCAL_CFLAGS) $(LOCAL_CFLAGS_$(NDK_BUILD_ARCH))
NDK_ASFLAGS_$(LOCAL_MODULE) := $(LOCAL_ASFLAGS) $(LOCAL_ASFLAGS_$(NDK_BUILD_ARCH))
NDK_LDFLAGS_$(LOCAL_MODULE) := $(LOCAL_LDLIBS) $(LOCAL_LDFLAGS)
NDK_CXXFLAGS_$(LOCAL_MODULE) := $(LOCAL_CPPFLAGS) $(LOCAL_RTTI_FLAG)

# Now look for features in LOCAL_CPP_FEATURES and enable them.

ifneq ($(findstring exceptions,$(LOCAL_CPPFLAGS)),)
NDK_CXXFLAGS_$(LOCAL_MODULE) += -fexceptions
endif

ifneq ($(findstring rtti,$(LOCAL_CPPFLAGS)),)
NDK_CXXFLAGS_$(LOCAL_MODULE) += -frtti
endif

ALL_OBJECT_FILES$(LOCAL_MODULE) :=

ifeq ($(NDK_BUILD_ARCH)$(NDK_ARM_MODE),armarm)
NDK_CFLAGS ::= -marm
else
ifeq ($(NDK_BUILD_ARCH),arm)
NDK_CFLAGS ::= -mthumb
endif
endif

ifeq ($(findstring lib,$(LOCAL_MODULE)),lib)
LOCAL_MODULE_FILENAME := $(LOCAL_MODULE)_emacs
else
LOCAL_MODULE_FILENAME := lib$(LOCAL_MODULE)_emacs
endif

# Since a shared library is being built, suffix the library with
# _emacs.  Otherwise, libraries already on the system will be found
# first, with potentially nasty consequences.

LOCAL_MODULE_FILENAME := $(LOCAL_MODULE_FILENAME).so

# Record this module's dependencies and exported includes and CFLAGS,
# and then add that of its dependencies.

include ndk-resolve.mk

# Then define rules to build all objects.
ALL_SOURCE_FILES = $(LOCAL_SRC_FILES) $(LOCAL_SRC_FILES_$(NDK_BUILD_ARCH))

# This defines all dependencies.
ALL_OBJECT_FILES$(LOCAL_MODULE) =

$(foreach source,$(ALL_SOURCE_FILES),$(eval $(call single-object-target,$(source))))

# Now define the rule to build the shared library.  Shared libraries
# link with all of the archive files from the static libraries on
# which they depend.

define define-module-rule
$(LOCAL_MODULE_FILENAME): $(ALL_OBJECT_FILES$(LOCAL_MODULE)) $(NDK_LOCAL_A_NAMES_$(LOCAL_MODULE)) $(NDK_WHOLE_A_NAMES_$(LOCAL_MODULE))
	$(NDK_BUILD_CC) $(1) $(2) -o $$@ -shared $(NDK_LDFLAGS$(LOCAL_MODULE)) $(NDK_SO_EXTRA_FLAGS_$(LOCAL_MODULE)) $(NDK_SO_DEFAULT_LDFLAGS)
endef

NDK_WHOLE_ARCHIVE_PREFIX = -Wl,--whole-archive
NDK_WHOLE_ARCHIVE_SUFFIX = -Wl,--no-whole-archive

$(eval $(call define-module-rule,$(ALL_OBJECT_FILES$(LOCAL_MODULE)) $(NDK_LOCAL_A_NAMES_$(LOCAL_MODULE)),$(and $(strip $(NDK_WHOLE_A_NAMES_$(LOCAL_MODULE))),$(NDK_WHOLE_ARCHIVE_PREFIX) $(NDK_WHOLE_A_NAMES_$(LOCAL_MODULE)) $(NDK_WHOLE_ARCHIVE_SUFFIX))))
