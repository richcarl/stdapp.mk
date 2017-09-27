# Makefile for building an Erlang application
# Copyright (C) 2014-2017 Klarna AB. Written by Richard Carlsson.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#
# Usage: make -C <app-directory> -f stdapp.mk [target]
#
# Targets:
#   build
#   tests
#   docs
#   install
#   clean
#   distclean
#   realclean
#   clean-tests
#   clean-docs
#
# Running 'make -f stdapp.mk' in an empty directory will create the file
# src/APPLICATION.app.src, taking the application name from the directory
# name. You can override this using 'make APPLICATION=... -f stdapp.mk'.
# Once the src/*.app.src (or ebin/*.app) file exists, the name of that file
# will be used for the application name. When compiling an Erlang program
# using stdapp.mk, the macro ?APPLICATION will be automatically defined. You
# can override the name of this macro to avoid collisions by setting the
# make variable APPLICATION_NAME_MACRO.
#
# The following is an example of a minimal top level Makefile for building
# all applications in the lib/ subdirectory:
#
#   TOP_DIR = $(CURDIR)
#   APPS = $(wildcard lib/*)
#   BUILD_TARGETS = $(APPS:lib/%=build-%)
#   .PHONY: all $(BUILD_TARGETS)
#   all: $(BUILD_TARGETS)
#   $(BUILD_TARGETS):
#           $(MAKE) -f $(TOP_DIR)/stdapp.mk -C $(patsubst build-%,lib/%,$@) \
#             -I $(TOP_DIR) ERL_DEPS_DIR=$(TOP_DIR)/build/$(@:build-%=%) \
#             build
#
# Run "make build-foo" to build only the application foo. Add similar rules
# for other targets like tests-foo, docs-foo, clean-foo, etc. Any specific
# APPLICATION.mk files are expected to be in $(TOP_DIR)/apps/. If you don't
# pass ERL_DEPS_DIR, the .d files will be placed in the source directory.
# Note that the $(MAKE) call runs from the app subdirectory, so it's best to
# use absolute paths based on TOP_DIR for the parameters.
#
# * define STDAPP_NO_GIT_TAG if you don't want to compute git tags
# * define STDAPP_FORCE_GIT_TAG_VSN if you want to always use git tags as vsn
# * define STDAPP_NO_VSN_MK if you want to ignore any vsn.mk files
# * define STDAPP_VSN_ADD_GIT_HASH if you want to add a git hash suffix
#   to the vsn (unless the vsn is equal to the git tag)
#

## DO NOT ADD ANY RULES ABOVE THIS LINE!
## this ensures that no include file accidentally overrides the default rule
.PHONY: all build tests clean docs distclean realclean
all: build

# read global configuration file, if it exists - not required to make clean
# (use the -I flag with Make to specify the directory for this file)
-include config.mk

# variable defaults
VPATH ?=
NODEPS_TARGETS ?=
ERL ?= erl
ERL_NOSHELL ?= erl -noshell +A0
ERLC ?= erlc
ESCRIPT ?= escript
EBIN_DIR ?= ebin
SRC_DIR ?= src
INCLUDE_DIR ?= include
PRIV_DIR ?= priv
DOC_DIR ?= doc
TEST_DIR ?= test
TEST_EBIN_DIR ?= $(TEST_DIR)
BIN_DIR ?= bin
ifndef ERL_DEPS_DIR
  ERL_TEST_DEPS_DIR ?= $(TEST_DIR)
else
  ERL_TEST_DEPS_DIR ?= $(ERL_DEPS_DIR)
endif
ERL_DEPS_DIR ?= $(SRC_DIR)
LIB_DIR ?= $(abspath ..)
PROGRESS ?= @echo -n '.'
GAWK ?= gawk
SED ?= sed
DEFAULT_VSN ?= 0.1

# figure out the application name, unless APPLICATION is already set
# (first check for src/*.app.src, then ebin/*.app, otherwise use the dirname)
ifndef APPLICATION
  appsrc = $(wildcard $(SRC_DIR)/*.app.src)
  ifneq ($(appsrc),)
    APPLICATION := $(patsubst $(SRC_DIR)/%.app.src,%,$(appsrc))
  else
    appfile = $(wildcard $(EBIN_DIR)/*.app)
    ifneq ($(appfile),)
      APPLICATION := $(patsubst $(EBIN_DIR)/%.app,%,$(appfile))
    else
      APPLICATION := $(notdir $(CURDIR))
    endif
  endif
endif
export APPLICATION
APP_SRC_FILE ?= $(SRC_DIR)/$(APPLICATION).app.src
APP_FILE ?= $(EBIN_DIR)/$(APPLICATION).app
APPLICATION_NAME_MACRO ?= APPLICATION

# ensure that all applications under lib are available to erlc when building
# (note that ERL_LIBS may be a path - don't assume it's a single directory)
ERL_LIBS ?= $(LIB_DIR)
export ERL_LIBS

# generic Erlang sources and targets
YRL_SOURCES := $(wildcard $(SRC_DIR)/*.yrl $(SRC_DIR)/*/*.yrl \
		 $(SRC_DIR)/*/*/*.yrl)
ERL_SOURCES := $(wildcard $(SRC_DIR)/*.erl $(SRC_DIR)/*/*.erl \
		 $(SRC_DIR)/*/*/*.erl)
ERL_TEST_SOURCES := $(wildcard $(TEST_DIR)/*.erl)

# read any vsn.mk for backwards compatibility with many existing applications
# NOTE: if you use vsn.mk, then add a .app file dependency like the following:
#
#   $(APP_FILE): vsn.mk
#
ifndef STDAPP_NO_VSN_MK
-include ./vsn.mk
  ifndef VSN
    # some apps define the <APPNAME>_VSN varable instead
    vsnvar=$(shell echo $(APPLICATION) | tr a-z A-Z)_VSN
    ifdef $(vsnvar)
      VSN := $($(vsnvar))
    endif
  endif
endif

ifdef STDAPP_NO_GIT_TAG
  GIT_TAG :=
else
  ifdef STDAPP_VSN_ADD_GIT_HASH
    longdesc=--long
  endif
  GIT_TAG := $(shell git describe --tags --always $(longdesc))
  ifdef STDAPP_FORCE_GIT_TAG_VSN
    VSN := $(GIT_TAG)
  endif
endif

# if VSN not yet defined, get nonempty vsn from any existing .app.src or
# .app file, use git tag, if any, or default (note that sed regexp matching
# is greedy, so the rightmost {vsn, "..."} in the input will be selected)
ifndef VSN
  VSN := $(shell echo '{vsn,"$(DEFAULT_VSN)"}' `cat $(APP_FILE) 2> /dev/null` '{vsn,"$(GIT_TAG)"}' `cat $(APP_SRC_FILE) 2> /dev/null` | $(SED) -n 's/.*{[[:space:]]*vsn[[:space:]]*,[[:space:]]*"\([^"][^"]*\)".*/\1/p')
endif

ifdef STDAPP_VSN_ADD_GIT_HASH
  ifneq ($(VSN),$(GIT_TAG))
    VSN := $(VSN)-g$(shell git rev-parse --short HEAD)
  endif
endif

# read any application-specific definitions and rules
-include ./app.mk

# read any system-specific definitions and rules for the application
# (use the -I flag with Make to specify the directory for these files)
-include apps/$(APPLICATION).mk

# read any local definitions and rules
-include stdapp.local.mk

# ensure sane default values if not already defined at this point
ERLC_FLAGS ?= +debug_info +warn_obsolete_guard +warn_export_all
YRL_FLAGS ?=
EDOC_OPTS ?= {def,{version,"$(VSN)"}},todo,no_packages

# automatically add the include directory to erlc options (the src directory
# is added so that modules under test/ can be compiled using the same rule)
ERLC_FLAGS += -I $(INCLUDE_DIR) -I $(SRC_DIR) -D$(APPLICATION_NAME_MACRO)="$(APPLICATION)"

# computed targets
YRL_OBJECTS := $(YRL_SOURCES:%.yrl=%.erl)
ERL_SOURCES += $(YRL_OBJECTS)
ERL_OBJECTS := $(addprefix $(EBIN_DIR)/, $(notdir $(ERL_SOURCES:%.erl=%.beam)))
ERL_TEST_OBJECTS := $(addprefix $(TEST_EBIN_DIR)/, $(notdir $(ERL_TEST_SOURCES:%.erl=%.beam)))
ERL_DEPS=$(ERL_OBJECTS:$(EBIN_DIR)/%.beam=$(ERL_DEPS_DIR)/%.d)
ERL_TEST_DEPS=$(ERL_TEST_OBJECTS:$(TEST_EBIN_DIR)/%.beam=$(ERL_TEST_DEPS_DIR)/%.d)
MODULES := $(sort $(ERL_OBJECTS:$(EBIN_DIR)/%.beam=%))

# comma-separated list of single-quoted module names
# (the comma/space variables are needed to work around Make's argument parsing)
comma := ,
space :=
space +=
MODULES_LIST := $(subst $(space),$(comma)$(space),$(patsubst %,'%',$(MODULES)))

# add the list of directories containing source files to VPATH (note that
# $(sort) removes duplicates; also ensure that at least $(ERL_DEPS_DIR) and
# $(SRC_DIR) are always present in the VPATH even if there are no sources)
VPATH := $(sort $(VPATH) $(dir $(ERL_SOURCES) $(ERL_TEST_SOURCES)) \
		$(SRC_DIR)/ $(ERL_DEPS_DIR)/ $(ERL_TEST_DEPS_DIR)/)

#
# Targets
#

.SUFFIXES: .erl .beam .yrl .d .app .app.src

.PRECIOUS: $(YRL_OBJECTS)

# read the .d file corresponding to each .erl file, UNLESS making clean!
NODEPS_TARGETS += clean distclean realclean clean-tests clean-docs
ifneq (,$(filter-out $(NODEPS_TARGETS),$(MAKECMDGOALS)))
  -include $(ERL_DEPS)
  # only read the .d file for test modules if actually building tests
  ifneq (,$(filter tests $(ERL_TEST_OBJECTS),$(MAKECMDGOALS)))
    -include $(ERL_TEST_DEPS)
  endif
endif

$(ERL_DEPS): | $(ERL_DEPS_DIR)
$(ERL_TEST_DEPS): | $(ERL_TEST_DEPS_DIR)

build: $(ERL_OBJECTS) $(APP_FILE)
	@$(ERL_NOSHELL) -eval 'erlang:halt(case file:consult("$(APP_FILE)") of {ok,_}->0; _->1 end)' || { echo '*** error: $(APP_FILE) is not readable'; exit 1; }

$(ERL_OBJECTS): | $(EBIN_DIR)

tests: $(ERL_TEST_OBJECTS)

$(ERL_TEST_OBJECTS): | $(TEST_EBIN_DIR)

realclean: distclean clean-docs

distclean: clean clean-deps

.PHONY: clean-deps
clean-deps:
	rm -f $(ERL_DEPS) $(ERL_TEST_DEPS)

clean: clean-tests
	rm -f $(ERL_OBJECTS) $(YRL_OBJECTS) $(APP_FILE)

.PHONY: clean-tests
clean-tests:
	rm -f $(ERL_TEST_OBJECTS)

docs: $(DOC_DIR)/edoc-info

$(DOC_DIR)/edoc-info: $(ERL_SOURCES) $(wildcard $(DOC_DIR)/*.edoc)
	$(PROGRESS)
	$(ERL_NOSHELL) -eval 'edoc:application($(APPLICATION), ".", [$(EDOC_OPTS)]), init:stop().'

.PHONY: clean-docs
clean-docs:
	rm -f $(DOC_DIR)/edoc-info $(DOC_DIR)/*.html $(DOC_DIR)/stylesheet.css $(DOC_DIR)/erlang.png

# create .app file by replacing {vsn, ...} and {modules, ...} in .app.src file,
# also handling the case when the value of vsn is a tuple (as used by rebar);
# MODULES_LIST will contain single quote characters, so must be in double quotes
# (note the special sed loop here to merge any multi-line modules declarations).
# The dependency on SRC_DIR will trigger a rebuild of the APP_FILE whenever
# source files are added or removed, but not when existing files are modified.
# Changes in source subdirectories are not currently detected.
$(APP_FILE): $(APP_SRC_FILE) $(SRC_DIR) | $(EBIN_DIR)
	$(PROGRESS)
	$(SED) -e 's/\({[[:space:]]*vsn[[:space:]]*,[[:space:]]*\)\({[^}]*}\)\?[^}]*}/\1"$(VSN)"}/' \
	    -e ':x;/{[[:space:]]*modules\([^}[:alnum:]][^}]*\)\?$$/{N;b x}' \
	    -e "s/\({[[:space:]]*modules[[:space:]]*,[[:space:]]*\)[^}]*}/\1[$(MODULES_LIST)]}/" \
	    $< > $@

# create a new .app.src file, or just clone the .app file if it already exists
# (note: overwriting is easier than a multi-line conditional in a recipe)
$(APP_SRC_FILE): | $(SRC_DIR)
	$(PROGRESS)
	echo >  $@ '{application,$(APPLICATION),'
	echo >> $@ ' [{description,"The $(APPLICATION) application"},'
	echo >> $@ '  {vsn,"$(VSN)"},'
	echo >> $@ '% {mod,{$(APPLICATION)_app,[]}},'
	echo >> $@ '  {modules,[]},'
	echo >> $@ '  {registered, []},'
	echo >> $@ '  {applications,[kernel,stdlib]},'
	echo >> $@ '  {env, []}'
	echo >> $@ ' ]}.'
	if [ -f $(APP_FILE) ]; then $(SED) -e 's/\({[[:space:]]*vsn[[:space:]]*,[[:space:]]*\)[^}]*}/\1"$(VSN)"}/' $(APP_FILE) > $(@); fi

# ensuring that target directories exist; use order-only prerequisites for this
$(sort $(EBIN_DIR) $(ERL_DEPS_DIR) $(ERL_TEST_DEPS_DIR) $(SRC_DIR) $(TEST_DIR)):
	mkdir -p $@

#
# Pattern rules
#

$(EBIN_DIR)/%.beam $(TEST_EBIN_DIR)/%.beam: %.erl
	$(PROGRESS)
	p=$(if $(findstring $<,$(ERL_TEST_SOURCES)),$(TEST_EBIN_DIR),$(EBIN_DIR)); $(ERLC) -pa "$$p" $(ERLC_FLAGS) -o $(@D) $<

%.erl: %.yrl
	$(PROGRESS)
	$(ERLC) $(YRL_FLAGS) -o $(@D) $<

# automatically generated dependencies for header files and local behaviours
# (there is no point in generating dependencies for behaviours in other
# applications, since we cannot cause them to be built from the current app)
# NOTE: currently doesn't find behaviour/transform modules in subdirs of src
$(ERL_DEPS_DIR)/%.d $(ERL_TEST_DEPS_DIR)/%.d: %.erl
	$(PROGRESS)
	d=$(if $(findstring $<,$(ERL_TEST_SOURCES)),$(TEST_EBIN_DIR),$(EBIN_DIR)); $(ERLC) $(ERLC_FLAGS) -o $(ERL_DEPS_DIR) -MP -MG -MF $@ -MT "$$d/$*.beam $@" $< && $(GAWK) -v d="$$d" '/^[ \t]*-(behaviou?r\(|compile\({parse_transform,)/ {match($$0, /-(behaviou?r\([ \t]*([^) \t]+)|compile\({parse_transform,[ \t]*([^} \t]+))/, a); m = (a[2] a[3]); if (m != "" && (getline x < ("$(SRC_DIR)/" m ".erl")) >= 0) print "\n" d "/$*.beam: $(EBIN_DIR)/" m ".beam"; else if (m != "" && (getline x < ("$(TEST_DIR)/" m ".erl")) >= 0) print "\n" d "/$*.beam: $(TEST_EBIN_DIR)/" m ".beam"}' < $< >> $@

#
# Installing
#

INSTALL_DIRS ?= $(EBIN_DIR) $(BIN_DIR) $(PRIV_DIR) $(INCLUDE_DIR)
INSTALL_DIRS += $(INSTALL_EXTRA_DIRS)

ALWAYS_INSTALL_FILES ?= README* NOTICE* LICENSE* COPYING* AUTHOR* CONTRIB*
INSTALL_FILES += $(ALWAYS_INSTALL_FILES)
INSTALL_FILES += $(INSTALL_EXTRA_FILES)

# this find-filter is used to strip files from copied INSTALL_DIRS directories
INSTALL_FILTER += -name "*.edoc" -o -name ".git*" -o -name ".svn*"

ERLANG_INSTALL_LIB_DIR ?= /tmp/lib/erlang/lib

INSTALL ?= install
INSTALL_DATA ?= $(INSTALL) -m 644
INSTALL_D ?= $(INSTALL) -d
CP_RECURSIVE ?= cp -r -d --preserve=mode --remove-destination

INSTALL_ROOT := $(DESTDIR)$(ERLANG_INSTALL_LIB_DIR)/$(APPLICATION)

install:
	$(INSTALL_D) $(INSTALL_ROOT)
	for file in $(INSTALL_FILES); do \
	  if [ -f $${file} ]; then $(INSTALL_DATA) -D $${file} $(INSTALL_ROOT)/$${file}; fi; done
	for dir in $(INSTALL_DIRS); do \
	  if [ -d $${dir} ]; then \
	    $(CP_RECURSIVE) -t $(INSTALL_ROOT) $${dir} && \
	    find $(INSTALL_ROOT)/$${dir} \( $(INSTALL_FILTER) \) -print0 | xargs -0 rm -f; \
	  fi; done
