stdapp.mk
=========

Generic Makefile for building Erlang applications. Distributed under the MIT
License (see the file LICENSE). Copyright (C) 2014-2017 Klarna AB. Written
by Richard Carlsson.

Prerequisites: GNU Make, GNU AWK (gawk).

Use a simple Makefile wrapper like this for local use within an application:

    # application-local Makefile
    include stdapp.mk

Predefined Make targets:

    build
    tests
    docs
    install
    clean
    distclean
    realclean
    clean-tests
    clean-docs

From a top level directory with a number of applications under a `lib/`
subdirectory, the following is a minimal example for building all
applications:

    # Top level Makefile
    TOP_DIR = $(CURDIR)
    APPS = $(wildcard lib/*)
    BUILD_TARGETS = $(APPS:lib/%=build-%)

    .PHONY: all $(BUILD_TARGETS)
    all: $(BUILD_TARGETS)

    $(BUILD_TARGETS):
            $(MAKE) -f $(TOP_DIR)/stdapp.mk -C $(patsubst build-%,lib/%,$@) \
              -I $(TOP_DIR) ERL_DEPS_DIR=$(TOP_DIR)/build/$(@:build-%=%) \
              build

Run `make build-foo` to build only the application `foo`. Add similar rules
for other targets like `tests`, `docs`, `clean`, etc.

 * Run with `-jN` for parallel builds. Add rules like `build-foo: build-bar`
   to control the build order of applications.

 * A top level `config.mk` (e.g., generated via autoconf) will automatically
   be included if it exists. The file `stdapp.local.mk` is also included if
   it exists, for local customizations such as additional targets for all
   apps. Use the `-I` flag to tell `make` to where to look for these files.

 * Additional rules and definitions needed for a specific application can be
   placed in a file `apps/$(APPLICATION).mk`, or in a file `app.mk` file in
   the application directory.

 * Header file dependencies are computed using the built-in facilities of
   `erlc`. If you don't pass `ERL_DEPS_DIR` as in the above example, the
   `.d` (dependency) files will be placed in the `ebin` directory of each
   application.

 * Note that the recursive `$(MAKE)` call runs from within the application
   directory, so it's best to use absolute paths based on `TOP_DIR` for the
   parameters passed from the top Makefile.

 * The VPATH feature of GNU Make is used to find source files even if they
   are located in subdirectories of the `src/` directory.

 * Dependencies on behaviour or parse transform modules within the same
   application will be detected automatically. For compile-time module
   dependencies between applications, add build order rules to the top
   Makefile.

 * VSN will be taken from any existing `vsn.mk` file,
   `$(APPLICATION).app.src`, or `$(APPLICATION).app` file in the
   application, or otherwise computed from the git tag (like Rebar does).

 * If no `$(APPLICATION).app.src` file exists, one will be created. (If an
   `$(APPLICATION).app` file exists, it will be used to create the
   `$(APPLICATION).app.src`. You should keep the `$(APPLICATION).app.src`
   file in version control, but not the `$(APPLICATION).app` file.)

 * The `$(APPLICATION).app` file is checked for readability to prevent nasty
   surprises.

The following is an example of a complementary `app.mk` file with additional
rules for an application containing a port program in C under `c_src`:

    build: $(PRIV_DIR)/foo_driver
    
    clean: clean_priv
    
    $(PRIV_DIR)/foo_driver: c_src/foo_driver.c | $(PRIV_DIR)
            $(CC) $(CFLAGS) -o $@ $<
    
    $(PRIV_DIR):
            mkdir -p $(PRIV_DIR)
    
    .PHONY: clean_priv
    clean_priv:
            rm -f $(PRIV_DIR)/foo_driver
