
# Defalut to running jobs in parallel, one for each CPU core
MAKEFLAGS += --output-sync=none
# Default to not echoing commands before running
MAKEFLAGS += --silent
# Disable as much built in file type builds as possible
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# Don't drop intermediate artifacts (saves rebulid time and aids debugging)
.SECONDARY:
.PRECIOUS: %.pdf %.sil %.toc %.dat %.inc
.DELETE_ON_ERROR:

# Deprecate direct usage under `make` without the CLI
ifeq ($(CASILE_CLI),)
$(error Use of CaSILE rule file inclusion outside of the CLI is deprecated!)
endif

# Run recipies in zsh wrapper, and all in one pass
SHELL := $(CASILEDIR)/make-shell.zsh
.SHELLFLAGS = target=$@
.ONESHELL:
.SECONDEXPANSION:

# Utility variables for later, http://blog.jgc.org/2007/06/escaping-comma-and-space-in-gnu-make.html
, := ,
space := $() $()
$(space) := $() $()
lparen := (
rparen := )

# Allow overriding executables used
INKSCAPE ?= inkscape
MAGICK ?= magick
PANDOC ?= pandoc
PERL ?= perl
POVRAY ?= povray
PYTHON ?= python
SED ?= sed
SILE ?= sile

include $(CASILEDIR)/rules/functions.mk
