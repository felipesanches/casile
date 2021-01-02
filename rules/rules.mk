# If called using the CaSILE CLI the init rules will be sourced before any
# project specific ones, then everything will be sourced in order. If people do
# a manual include to rules they may or may not know to source the
# initilazation rules first. this is to warn them.
ifeq ($(CASILEDIR),)
$(error Please initialize CaSILE by sourcing casile.mk first, then include your project rules, then source this rules.mk file)
endif

PUBDIR ?= $(PROJECTDIR)/pub
PUBLISHERDIR ?= $(CASILEDIR)

# Set the language if not otherwise set
LANGUAGE ?= en

# Localization functions (source is a key => val file _and_ its inverse)
-include $(CASILEDIR)rules/$(LANGUAGE).mk $(CASILEDIR)rules/$(LANGUAGE)-reversed.mk

# Empty recipies for anything we _don't_ want to bother rebuilding:
$(MAKEFILE_LIST):;

MARKDOWNSOURCES := $(call find,*.md)
LUASOURCES := $(call find,*.lua)
MAKESOURCES := $(call find,[Mm]akefile*)
YAMLSOURCES := $(call find,*.yml)

# # Find stuff that could be built based on what has matching YML and a MD components
SOURCES_DEF := $(filter $(basename $(notdir $(MARKDOWNSOURCES))),$(basename $(notdir $(YAMLSOURCES))))
SOURCES ?= $(SOURCES_DEF)
TARGETS ?= $(SOURCES)

ISBNS != $(and $(YAMLSOURCES),$(YQ) -M -e -r '.identifier[]? | select(.scheme == "ISBN-13").text' $(YAMLSOURCES))

# List of targets that don't have content but should be rendered anyway
MOCKUPSOURCES ?=
MOCKUPBASE ?= $(firstword $(SOURCES))
MOCKUPFACTOR ?= 1

# List of figures that need building prior to content
FIGURES ?=

# Default output formats and parameters (often overridden)
FORMATS ?= pdfs epub mobi odt docx web play app
BLEED ?= 3
TRIM ?= 10
NOBLEED ?= 0
NOTRIM ?= 0
PAPERWEIGHT ?= 60
STAPLECOUNT ?= 2
COILSPACING ?= 12
COILWIDTH ?= 8
COILCOLOR ?= rgb<.7,.7,.7>
COVERGRAVITY ?= Center
SCENELIGHT ?= rgb<1,1,1>
SCENEX ?= $(call scale,2400)
SCENEY ?= $(call scale,3200)

# Because sometimes the same base content can be postprocessed multiple ways
EDITS ?= $(_withverses) $(_withoutfootnotes) $(_withoutlinks)

# Build mode flags
DRAFT ?= false # Take shortcuts, scale things down, be quick about it
LAZY ?= false # Pretend to do things we didn't
DIFF ?= false # Show differences to parent branch in build
STATSMONTHS ?= 1 # How far back to look for commits when building stats
DEBUG ?= false # Use SILE debug flags, set -x, and the like
DEBUGTAGS ?= casile # Specific debug flags to set
COVERS ?= true # Build covers?
MOCKUPS ?= true # Render mockup books in project
SCALE ?= 17 # Reduction factor for draft builds
HIDPI_DEF := $(call scale,1200) # Default DPI for generated press resources
HIDPI ?= $(HIDPI_DEF)
LODPI_DEF := $(call scale,300) # Default DPI for generated consumer resources
LODPI ?= $(LODPI_DEF)
SORTORDER ?= meta # Sort series by: none, alphabetical, date, meta, manual

# Set default output format(s)
LAYOUTS ?= a4-$(_print)
EDITIONS ?=

# Add any specifically targeted output layouts
GOALLAYOUTS := $(sort $(filter-out -,$(foreach GOAL,$(MAKECMDGOALS),$(call parse_layout,$(GOAL)))))
LAYOUTS += $(GOALLAYOUTS)

ifneq ($(filter ci %.promotionals %.web %.epub %.play %.app,$(MAKECMDGOALS)),)
LAYOUTS += $(call pattern_list,$(PLACARDS),-$(_print))
endif

# Categorize supported outputs
PAPERSIZES := $(call localize,$(subst layouts/,,$(notdir $(basename $(wildcard $(CASILEDIR)layouts/*.lua)))))
BINDINGS = $(call localize,print paperback hardcover coil stapled)
DISPLAYS := $(_app) $(_screen)
PLACARDS := $(_square) $(_wide) $(_banner) epub

FAKEPAPERSIZES := $(DISPLAYS) $(PLACARDS)
REALPAPERSIZES := $(filter-out $(FAKEPAPERSIZES),$(PAPERSIZES))
FAKELAYOUTS := $(call pattern_list,$(PLACARDS),-$(_print))
REALLAYOUTS := $(call pattern_list,$(REALPAPERSIZES),$(foreach BINDING,$(BINDINGS),-$(BINDING))) $(call pattern_list,$(DISPLAYS),-$(_print))
ALLLAYOUTS := $(REALLAYOUTS) $(FAKELAYOUTS)
UNBOUNDLAYOUTS := $(call pattern_list,$(PAPERSIZES),-$(_print))
BOUNDLAYOUTS := $(filter-out $(UNBOUNDLAYOUTS),$(ALLLAYOUTS))

RENDERINGS := $(_3d)-$(_front) $(_3d)-$(_back) $(_3d)-$(_pile)
RENDERED_DEF := $(filter $(call pattern_list,$(REALPAPERSIZES),-%),$(LAYOUTS))
RENDERED ?= $(RENDERED_DEF)
RENDERED += $(GOALLAYOUTS)

# Over-ride entr arguments, defaults to just clear
# Add -r to kill and restart jobs on activity
# And -p to wait for activity on first invocation
ENTRFLAGS := -c -r

# POVray's progress status output doesn't play nice with Gitlab's CI logging
ifneq ($(CI),)
POVFLAGS += -V
endif

# List of extra m4 macro files to apply to every source
M4MACROS ?=
PROJECTMACRO := $(wildcard $(PROJECT).m4)

# List of extra YAML meta data files to splice into each book
METADATA ?=
PROJECTYAML_DEF := $(wildcard $(PROJECT).yml)
PROJECTYAML ?= $(PROJECTYAML_DEF)

# Extra lua files to include before processing documents
LUAINCLUDES += .casile.lua
PROJECTLUA := $(wildcard $(PROJECT).lua)

# Primary libraries to include (loaded in reverse order so this one is first)
LUALIBS += $(CASILEDIR)casile.lua

# Extensible list of files for git to ignore
IGNORES += $(PROJECTCONFIGS)
IGNORES += $(LUAINCLUDES)
IGNORES += $(FIGURES)
IGNORES += $(PUBLISHERLOGO) $(PUBLISHEREMBLUM)
IGNORES += $(call pattern_list,$(PROJECT) $(SOURCES),$(PAPERSIZES),*)
IGNORES += $(call pattern_list,$(SOURCES),$(foreach FORMAT,$(FORMATS),.$(FORMAT)))
IGNORES += $(call pattern_list,$(ISBNS),_* .epub)
IGNORES += $(INTERMEDIATES)

# Tell sile to look here for stuff before its internal stuff
SILEPATH += $(CASILEDIR)

# Extra arguments to pass to Pandoc
PANDOCARGS ?= --wrap=preserve --markdown-headings=atx --top-level-division=chapter
PANDOCARGS += --reference-location=section
PANDOCFILTERARGS ?= --from markdown-space_in_atx_header+ascii_identifiers --to markdown-smart

# For when perl one-liners need Unicode compatibility
PERLARGS ?= -Mutf8 -CS

# Extra arguments for Image Magick
MAGICKARGS ?= -define profile:skip="*"

# Figure out if we're being run from
ATOM != env | $(GREP) -l ATOM_
ifneq ($(ATOM),)
DRAFT = true
endif

# Set default document class
DOCUMENTCLASS ?= cabook
DOCUMENTOPTIONS += binding=$(call unlocalize,$(or $(call parse_binding,$@),$(firstword $(BINDINGS))))

# Default template for setting up Gitlab CI runners
CITEMPLATE ?= $(CASILEDIR)travis.yml
CICONFIG ?= .travis.yml

# List of files that persist across make clean
PROJECTCONFIGS :=

ifeq ($(DRAFT),true)
$(MAKECMDGOALS): force
endif

# For watch targets, treat extra parameters as things to pass to the next make
ifeq (watch,$(firstword $(MAKECMDGOALS)))
WATCHARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(WATCHARGS):;@:)
endif

export PATH := $(CASILEDIR)scripts:$(PATH):$(shell $(PYTHON) -c "import site; print(site.getsitepackages()[0]+'/scripts')")
export HOSTNAME := $(shell hostname)
export PROJECT := $(PROJECT)

LOCALSILE ?= $(HOME)/projects/sile-typesetter/sile
ifeq ($(DEBUG),true)
SILE = $(LOCALSILE)/sile
$(call prepend,SILEPATH,$(LOCALSILE) $(LOCALSILE)/core )
SILEFLAGS += -t
.SHELLFLAGS += -x
endif

# Pass debug tags on to SILE
ifdef DEBUGTAGS
SILEFLAGS += -d $(subst $( ),$(,),$(strip $(DEBUGTAGS)))
endif

# Most CI runners need help getting the branch name because of sparse checkouts
BRANCH := $(or $(CI_COMMIT_REF_NAME),$(shell $(GIT) rev-parse --abbrev-ref HEAD))
TAG := $(or $(CI_COMMIT_TAG),$(shell $(GIT) describe --tags --exact-match 2>/dev/null))
ALLTAGS := $(strip $(CI_COMMIT_TAG) $(shell $(GIT) tag --points-at HEAD | $(XARGS) echo))

# Add mock-ups to sources
ifeq ($(strip $(MOCKUPS)),true)
SOURCES += $(MOCKUPSOURCES)
endif

# Probe for available sources relevant to each target once
$(foreach SOURCE,$(SOURCES),$(eval TARGETMACROS_$(SOURCE) := $(wildcard $(SOURCE).lua)))
$(foreach SOURCE,$(SOURCES),$(eval TARGETYAMLS_$(SOURCE) := $(wildcard $(SOURCE).yml)))
$(foreach SOURCE,$(SOURCES),$(eval TARGETLUAS_$(SOURCE) := $(wildcard $(SOURCE).lua)))

.PHONY: all
all: $(FORMATS)

define format_template =
.PHONY: $(1)
$(1): $(call pattern_list,$(2),.$(1))
endef

$(foreach FORMAT,$(FORMATS),$(eval $(call format_template,$(FORMAT),$(TARGETS))))

PERSOURCEPDFS := $(call pattern_list,$(SOURCES),.pdfs)
.PHONY: $(PERSOURCEPDFS)
$(PERSOURCEPDFS): %.pdfs: $(call pattern_list,$$*,$(LAYOUTS),.pdf) $(and $(EDITIONS),$(call pattern_list,$$*,$(EDITIONS),$(LAYOUTS),.pdf))

# Setup target dependencies to mimic stages of a CI pipeline
ifeq ($(MAKECMDGOALS),ci)
CI ?= 1
pdfs: debug
renderings promotionals: pdfs
endif

.PHONY: ci
ci: debug pdfs renderings promotionals

.PHONY: renderings
renderings: $(call pattern_list,$(TARGETS),.renderings)

PERSOURCERENDERINGS := $(call pattern_list,$(SOURCES),.renderings)
.PHONY: $(PERSOURCERENDERINGS)
$(PERSOURCERENDERINGS): %.renderings: $(call pattern_list,$$*,$(RENDERED),$(RENDERINGS),.jpg) $(and $(EDITIONS),$(call pattern_list,$$*,$(EDITIONS),$(RENDERED),$(RENDERINGS),.jpg))

.PHONY: promotionals
promotionals: $(call pattern_list,$(TARGETS),.promotionals)

PERSOURCEPROMOTIONALS := $(call pattern_list,$(SOURCES),.promotionals)
.PHONY: $(PERSOURCEPROMOTIONALS)
$(PERSOURCEPROMOTIONALS): %.promotionals: $(call pattern_list,$$*,$(PLACARDS),-$(_poster).jpg) $$*-icon.png

# If a series, add some extra dependencies to convenience builds
ifneq ($(words $(TARGETS)),1)
promotionals: series_promotionals
renderings: series_renderings
endif

.PHONY: series_promotionals
series_promotionals: $(PROJECT)-epub-$(_poster)-$(_montage).jpg $(PROJECT)-$(_square)-$(_poster)-$(_montage).jpg

.PHONY: series_renderings
series_renderings: $(call pattern_list,$(PROJECT),$(RENDERED),-$(_3d)-$(_montage).jpg)

$(PROJECT)-%-$(_poster)-$(_montage).png: $$(call pattern_list,$(SOURCES),%,-$(_poster).png) $(firstword $(SOURCES))-%-$(_geometry).sh
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		montage \
		$(filter %.png,$^) \
		-geometry $${pagewpm}x$${pagehpm}+0+0 \
		$@

.PHONY: clean
clean: emptypub
	$(GIT) clean -xf $(foreach CONFIG,$(PROJECTCONFIGS),-e $(CONFIG))

emptypub: | $(require_pubdir)
	rm -f $(PUBDIR)/*

.PHONY: debug
debug:
	echo "ALLLAYOUTS = $(ALLLAYOUTS)"
	echo "ALLTAGS = $(ALLTAGS)"
	echo "BINDINGS = $(BINDINGS)"
	echo "BOUNDLAYOUTS = $(BOUNDLAYOUTS)"
	echo "CASILEDIR = $(CASILEDIR)"
	echo "CICONFIG = $(CICONFIG)"
	echo "CITEMPLATE = $(CITEMPLATE)"
	echo "DEBUG = $(DEBUG)"
	echo "DEBUGTAGS = $(DEBUGTAGS)"
	echo "DIFF = $(DIFF)"
	echo "DOCUMENTCLASS = $(DOCUMENTCLASS)"
	echo "DOCUMENTOPTIONS = $(DOCUMENTOPTIONS)"
	echo "DRAFT = $(DRAFT)"
	echo "EDITIONS = $(EDITIONS)"
	echo "EDITS = $(EDITS)"
	echo "FAKELAYOUTS = $(FAKELAYOUTS)"
	echo "FAKEPAPERSIZES = $(FAKEPAPERSIZES)"
	echo "FIGURES = $(FIGURES)"
	echo "FORMATS = $(FORMATS)"
	echo "GOALLAYOUTS = $(GOALLAYOUTS)"
	echo "ISBNS = $(ISBNS)"
	echo "LANGUAGE = $(LANGUAGE)"
	echo "LAYOUTS = $(LAYOUTS)"
	echo "LUAINCLUDES = $(LUAINCLUDES)"
	echo "LUALIBS = $(LUALIBS)"
	echo "LUASOURCES = $(LUASOURCES)"
	echo "M4MACROS = $(M4MACROS)"
	echo "MAKECMDGOALS = $(MAKECMDGOALS)"
	echo "MAKEFILE_LIST = $(MAKEFILE_LIST)"
	echo "MAKESOURCES = $(MAKESOURCES)"
	echo "MARKDOWNSOURCES = $(MARKDOWNSOURCES)"
	echo "METADATA = $(METADATA)"
	echo "MOCKUPBASE = $(MOCKUPBASE)"
	echo "MOCKUPFACTOR = $(MOCKUPFACTOR)"
	echo "MOCKUPSOURCES = $(MOCKUPSOURCES)"
	echo "PANDOCARGS = $(PANDOCARGS)"
	echo "PAPERSIZES = $(PAPERSIZES)"
	echo "PARENT = $(PARENT)"
	echo "PLAYSOURCES = $(PLAYSOURCES)"
	echo "PROJECT = $(PROJECT)"
	echo "PROJECTCONFIGS = $(PROJECTCONFIGS)"
	echo "REALLAYOUTS = $(REALLAYOUTS)"
	echo "REALPAPERSIZES = $(REALPAPERSIZES)"
	echo "RENDERED = $(RENDERED)"
	echo "SILE = $(SILE)"
	echo "SILEFLAGS = $(SILEFLAGS)"
	echo "SILEPATH = $(SILEPATH)"
	echo "SOURCES = $(SOURCES)"
	echo "TAG = $(TAG)"
	echo "TARGETS = $(TARGETS)"
	echo "UNBOUNDLAYOUTS = $(UNBOUNDLAYOUTS)"
	echo "YAMLSOURCES = $(YAMLSOURCES)"
	echo "urlinfo = $(call urlinfo,$(PROJECT))"
	echo "versioninfo = $(call versioninfo,$(PROJECT))"

.PHONY: force
force: ;

.PHONY: fail

.PHONY: list
list:
	$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2> /dev/null |
		$(AWK) -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' |
		$(SORT) |
		$(EGREP) -v -e '^[^[:alnum:]]' -e '^$@$$' |
		$(XARGS)

.PHONY: $(SOURCES)

REALSOURCES := $(filter-out $(MOCKUPSOURCES),$(SOURCES))
$(REALSOURCES): $(foreach FORMAT,$(FORMATS),$$@.$(FORMAT))
$(MOCKUPSOURCES): $(foreach FORMAT,$(filter pdfs,$(FORMATS)),$$@.$(FORMAT))

.PHONY: figures
figures: $(FIGURES)

$(PUBDIR):
	mkdir -p $@

.PHONY: update_toolkits
update_toolkits: update_casile

.PHONY: upgrade_toolkits
upgrade_toolkits: upgrade_casile

.PHONY: upgrade_repository
upgrade_repository: upgrade_toolkits $(CICONFIG)_current .gitattributes

.PHONY: upgrade_casile
upgrade_casile: $(CASILEDIR)upgrade-lua.sed $(CASILEDIR)upgrade-make.sed $(CASILEDIR)upgrade-yaml.sed $(CASILEDIR)upgrade-markdown.sed
	$(call munge,$(LUASOURCES),$(SED) -f $(filter %-lua.sed,$^),Replace old Lua variables and functions with new namespaces)
	$(call munge,$(MAKESOURCES),$(SED) -f $(filter %-make.sed,$^),Replace old Makefile variables and functions with new namespaces)
	$(call munge,$(YAMLSOURCES),$(SED) -f $(filter %-yaml.sed,$^),Replace old YAML key names and data formats)
	export SKIPM4=false
	$(call munge,$(MARKDOWNSOURCES),$(SED) -f $(filter %-markdown.sed,$^),Replace obsolete Markdown syntax)

PROJECTCONFIGS += .editorconfig
.editorconfig: $(CASILEDIR)editorconfig
	$(call skip_if_tracked,$@)
	cp $< $@

PROJECTCONFIGS += .gitignore
.gitignore: $(CASILEDIR)gitignore $(MAKEFILE_LIST) | $(require_pubdir)
	$(call skip_if_tracked,$@)
	cp $< $@
	$(foreach IGNORE,$(IGNORES),echo '$(IGNORE)' >> $@;)

.gitattributes: $(MAKEFILE_LIST)
	$(GIT) diff-index --quiet --cached HEAD || exit 1 # die if anything already staged
	$(GIT) diff-files --quiet -- $@ || exit 1 # die if this file has uncommitted changes
	for ft in md yml; do
		line="*.$${ft} linguist-detectabale=true"
		$(GREP) -qxF "$${line}" $@ || echo $${line} >> $@
		$(GIT) add -- $@
	done
	$(GIT) diff-index --quiet --cached HEAD || $(GIT) commit -m "[auto] Configure linguist file types for statistics"

$(CICONFIG): $(CITEMPLATE)
	$(GIT) diff-index --quiet --cached HEAD || exit 1 # die if anything already staged
	$(GIT) diff-files --quiet -- $@ || exit 1 # die if this file has uncommitted changes
	cat $< | \
		$(call ci_setup) | \
		$(SPONGE) $@
	$(GIT) add -- $@
	$(GIT) diff-index --quiet --cached HEAD || $(GIT) commit -m "[auto] Rebuild CI config file"

# Pass or fail target showing whether the CI config is up to date
.PHONY: $(CICONFIG)_current
$(CICONFIG)_current: $(CICONFIG)
	$(GIT) update-index --refresh --ignore-submodules ||:
	$(GIT) diff-files --quiet -- $<

# Reset file timestamps to git history to avoid unnecessary builds
.PHONY: time_warp
time_warp:
	$(call time_warp,$(PROJECTDIR))

# Some layouts have matching extra resources to build such as covers
ifneq ($(strip $(COVERS)),false)
$(PERSOURCEPDFS): %.pdfs: $$(call pattern_list,$$*,$(filter %-$(_paperback),$(LAYOUTS)),$(_binding),.pdf)
$(PERSOURCEPDFS): %.pdfs: $$(call pattern_list,$$*,$(filter %-$(_hardcover),$(LAYOUTS)),$(_case) $(jacket),.pdf)
$(PERSOURCEPDFS): %.pdfs: $$(call pattern_list,$$*,$(filter %-$(_coil),$(LAYOUTS)),$(_cover),.pdf)
$(PERSOURCEPDFS): %.pdfs: $$(call pattern_list,$$*,$(filter %-$(_stapled),$(LAYOUTS)),$(_binding),.pdf)
endif

# Some layouts have matching resources that need to be built first and included
coverpreq = $(and $(filter true,$(COVERS)),$(filter $(_print),$(call parse_binding,$1)),$(filter-out $(DISPLAYS) $(PLACARDS),$(call parse_papersize,$1)),$(basename $1)-$(_cover).pdf)

# Order is important here, these are included in reverse order so early supersedes late
onpaperlibs = $(TARGETLUAS_$(call parse_bookid,$1)) $(PROJECTLUA) $(CASILEDIR)layouts/$(call unlocalize,$(call parse_papersize,$1)).lua $(LUALIBS)

MOCKUPPDFS := $(call pattern_list,$(MOCKUPSOURCES),$(REALLAYOUTS),.pdf)
$(MOCKUPPDFS): %.pdf: $$(call mockupbase,$$@)
	$(PDFTK) A=$(filter %.pdf,$^) cat $(foreach P,$(shell seq 1 $(call pagecount,$@)),A2-2) output $@

FULLPDFS := $(call pattern_list,$(REALSOURCES),$(REALLAYOUTS),.pdf)
FULLPDFS += $(call pattern_list,$(REALSOURCES),$(EDITS),$(REALLAYOUTS),.pdf)
$(FULLPDFS): %.pdf: %.sil $$(call coverpreq,$$@) .casile.lua $$(call onpaperlibs,$$@) $(LUAINCLUDES) | $(require_pubdir)
	$(call skip_if_lazy,$@)
	$(DIFF) && $(SED) -e 's/\\\././g;s/\\\*/*/g' -i $< ||:
	export SILE_PATH="$(subst $( ),;,$(SILEPATH))"
	# If in draft mode don't rebuild for TOC and do output debug info, otherwise
	# account for TOC $(_issue): https://github.com/simoncozens/sile/issues/230
	if $(DRAFT); then
		$(SILE) $(SILEFLAGS) $< -o $@
	else
		export pg0=$(call pagecount,$@)
		$(SILE) $(SILEFLAGS) $< -o $@
		# Note this page count can't be in Make because of expansion order
		export pg1=$$($(PDFINFO) $@ | $(AWK) '$$1 == "Pages:" {print $$2}' || echo 0)
		[[ $${pg0} -ne $${pg1} ]] && $(SILE) $(SILEFLAGS) $< -o $@ ||:
		export pg2=$$($(PDFINFO) $@ | $(AWK) '$$1 == "Pages:" {print $$2}' || echo 0)
		[[ $${pg1} -ne $${pg2} ]] && $(SILE) $(SILEFLAGS) $< -o $@ ||:
	fi
	# If we have a special cover page for this format, swap it out for the half title page
	coverfile=$(filter %-$(_cover).pdf,$^)
	if $(COVERS) && [[ -f $${coverfile} ]]; then
		$(PDFTK) $@ dump_data_utf8 output $*.dat
		$(PDFTK) C=$${coverfile} B=$@ cat C1 B2-end output $*.tmp.pdf
		$(PDFTK) $*.tmp.pdf update_info_utf8 $*.dat output $@
		rm $*.tmp.pdf
	fi
	$(addtopub)

# Apostrophe Hack, see https://github.com/simoncozens/sile/issues/355
ifeq ($(LANGUAGE),tr)
ah := $(PERL) $(PERLARGS) -pne '/^\#/ or s/(?<=\p{L})’(?=\p{L})/\\ah{}/g' |
endif

FULLSILS := $(call pattern_list,$(SOURCES),$(REALLAYOUTS),.sil)
FULLSILS += $(call pattern_list,$(SOURCES),$(EDITS),$(REALLAYOUTS),.sil)
$(FULLSILS): private PANDOCFILTERS += --filter=$(CASILEDIR)pandoc-filters/svg2pdf.py
$(FULLSILS): private THISEDITS = $(call parse_edits,$@)
$(FULLSILS): private PROCESSEDSOURCE = $(call pattern_list,$(call parse_bookid,$@),$(_processed),$(and $(THISEDITS),-$(THISEDITS)).md)
$(FULLSILS): %.sil: $$(PROCESSEDSOURCE) $$(call pattern_list,$$(call parse_bookid,$$@),-manifest.yml -$(_verses)-$(_sorted).json -url.png) $(CASILEDIR)template.sil | $$(call onpaperlibs,$$@)
	$(PANDOC) --standalone \
			$(PANDOCARGS) \
			$(PANDOCFILTERS) \
			-V documentclass="$(DOCUMENTCLASS)" \
			$(if $(DOCUMENTOPTIONS),-V classoptions="$(call join_with,$(,),$(DOCUMENTOPTIONS))",) \
			-V metadatafile="$(filter %-manifest.yml,$^)" \
			-V versesfile="$(filter %-$(_verses)-$(_sorted).json,$^)" \
			-V versioninfo="$(call versioninfo,$@)" \
			-V urlinfo="$(call urlinfo,$@)" \
			-V qrimg="./$(filter %-url.png,$^)" \
			$(foreach LUA,$(call reverse,$(filter %.lua,$|)), -V script=$(subst $(CASILEDIR),,$(basename $(LUA)))) \
			--template=$(filter %.sil,$^) \
			--from=markdown \
			--to=sile \
			$(filter %-manifest.yml,$^) =(< $< $(call ah) $(call pre_sile_markdown_hook)) |
		$(call sile_hook) > $@

# Send some environment data to a common Lua file to be pulled into all SILE runs
.casile.lua:
	cat <<- EOF > $@
		package.path = package.path .. ";/?.lua;/?/init.lua"
		CASILE = {}
		CASILE.casiledir = "$(CASILEDIR)"
		CASILE.publisher = "casile"
	EOF

INTERMEDIATES += $(pattern_list *,$(EDITS),.md)

WITHVERSEFILTER := $(CASILEDIR)pandoc-filters/withverses.lua
SOURCESWITHVERSES := $(call pattern_list,$(SOURCES),-$(_processed)-$(_withverses).md)
$(SOURCESWITHVERSES): private PANDOCFILTERS += --lua-filter=$(WITHVERSEFILTER)
$(SOURCESWITHVERSES): private PANDOCFILTERS += -M versedatafile="$(filter %-$(_verses)-$(_text).yml,$^)"
$(SOURCESWITHVERSES): $$(call parse_bookid,$$@)-$(_verses)-$(_text).yml $(WITHVERSEFILTER)

SOURCESWITHOUTFOOTNOTES := $(call pattern_list,$(SOURCES),-$(_processed)-$(_withoutfootnotes).md)
$(SOURCESWITHOUTFOOTNOTES): private PANDOCFILTERS += --lua-filter=$(CASILEDIR)pandoc-filters/withoutfootnotes.lua
$(SOURCESWITHOUTFOOTNOTES): private PANDOCFILTERS += --lua-filter=$(CASILEDIR)pandoc-filters/withoutlinks.lua

SOURCESWITHOUTLINKS := $(call pattern_list,$(SOURCES),-$(_processed)-$(_withoutlinks).md)
$(SOURCESWITHOUTLINKS): private PANDOCFILTERS += --lua-filter=$(CASILEDIR)pandoc-filters/withoutlinks.lua

SOURCESWITHEDITS := $(SOURCESWITHVERSES) $(SOURCESWITHOUTFOOTNOTES) $(SOURCESWITHOUTLINKS)
$(SOURCESWITHEDITS): $$(call strip_edits,$$@)
	$(PANDOC) --standalone \
		$(PANDOCARGS) $(PANDOCFILTERS) $(PANDOCFILTERARGS) \
		$(filter %.md,$^) -o $@

# Configure SILE arguments to include common Lua library
SILEFLAGS += $(foreach LUAINCLUDE,$(call reverse,$(LUAINCLUDES)),-I $(LUAINCLUDE))

preprocess_macros = $(CASILEDIR)casile.m4 $(M4MACROS) $(PROJECTMACRO) $(TARGETMACROS_$1)

INTERMEDIATES += *-$(_processed).md
%-$(_processed).md: %.md $(wildcard %-$(_chapters)/*.md) $$(call preprocess_macros,$$*) $$(wildcard $$*-bolumler/*.md) | figures
	if $(DIFF) && $(if $(PARENT),true,false); then
		branch2criticmark.zsh $(PARENT) $<
	else
		$(M4) $(filter %.m4,$^) $<
	fi |
		renumber_footnotes.pl |
		$(and $(HEAD),head -n$(HEAD) |) \
		$(call link_verses) |
		$(PERL) $(PERLARGS) -pne "s/(?<=[\)\}])'/’/g" | # Work around Pandoc bug, see https://github.com/jgm/pandoc/issues/5385
		$(call criticToSile) |
		$(PANDOC) $(PANDOCARGS) $(PANDOCFILTERS) $(PANDOCFILTERARGS) |
		$(call markdown_hook) > $@

%-$(_booklet).pdf: %-$(_spineless).pdf | $(require_pubdir)
	$(PDFBOOK2) --short-edge --paper="{$(call pageh,$<)pt,$$(($(call pagew,$<)*2))pt}" -- $<
	mv $*-book.pdf $@
	$(addtopub)

%-2end.pdf: %.pdf
	$(PDFTK) $< cat 2-end output $@

%-2up.pdf: %-$(_cropped)-2end.pdf
	$(PDFJAM) --nup 2x1 --noautoscale true --paper a4paper --landscape --outfile $@ -- $<

%-topbottom.pdf: %-set1.pdf %-set2.pdf
	$(PDFTK) A=$(word 1,$^) B=$(word 2,$^) shuffle A B output $@

%-a4proof.pdf: %-topbottom.pdf | $(require_pubdir)
	$(PDFJAM) --nup 1x2 --noautoscale true --paper a4paper --outfile $@ -- $<
	$(addtopub)

%-cropleft.pdf: %.pdf | $$(geometryfile)
	$(sourcegeometry)
	t=$$(echo "$${trimpt} * 100" | $(BC))
	s=$$(echo "$${spinept} * 100 / 4" | $(BC))
	w=$$(echo "$(call pagew,$<) * 100 - $${t} + $${s}" | $(BC))
	h=$$(echo "$(call pageh,$<) * 100" | $(BC))
	$(PODOFOBOX) $< $@ media 0 0 $${w} $${h}

%-cropright.pdf: %.pdf | $$(geometryfile)
	$(sourcegeometry)
	t=$$(echo "$${trimpt} * 100" | $(BC))
	s=$$(echo "$${spinept} * 100 / 4" | $(BC))
	w=$$(echo "$(call pagew,$<) * 100 - $$t + $$s" | $(BC))
	h=$$(echo "$(call pageh,$<) * 100" | $(BC))
	$(PODOFOBOX) $< $@ media $$(($$t-$$s)) 0 $$w $$h

%-$(_spineless).pdf: %-$(_odd)-cropright.pdf %-$(_even)-cropleft.pdf
	$(PDFTK) A=$(word 1,$^) B=$(word 2,$^) shuffle A B output $@

%-$(_cropped).pdf: %.pdf | $$(geometryfile) $(require_pubdir)
	$(sourcegeometry)
	t=$$(echo "$${trimpt} * 100" | $(BC))
	w=$$(echo "$(call pagew,$<) * 100 - $${t} * 2" | $(BC))
	h=$$(echo "$(call pageh,$<) * 100 - $${t} * 2" | $(BC))
	$(PODOFOBOX) $< $@ media $${t} $${t} $${w} $${h}
	$(addtopub)

%-set1.pdf: %.pdf
	$(PDFTK) $< cat 1-$$(($(call pagecount,$<)/2)) output $@

%-set2.pdf: %.pdf
	$(PDFTK) $< cat $$(($(call pagecount,$<)/2+1))-end output $@

%-$(_even).pdf: %.pdf
	$(PDFTK) $< cat even output $@

%-$(_odd).pdf: %.pdf
	$(PDFTK) $< cat odd output $@

.PHONY: normalize_lua
normalize_lua: $(LUASOURCES)
	$(call munge,$^,$(SED) -e 's/function */function /g',Normalize Lua coding style)

.PHONY: normalize_markdown
normalize_markdown: $(MARKDOWNSOURCES)
	$(call munge,$(filter %.md,$^),msword_escapes.pl,Fixup bad MS word typing habits that Pandoc tries to preserve)
	$(call munge,$(filter %.md,$^),lazy_quotes.pl,Replace lazy double single quotes with real doubles)
	$(call munge,$(filter %.md,$^),figure_dash.pl,Convert hyphens between numbers to figure dashes)
	$(call munge,$(filter %.md,$^),italic_reorder.pl,Fixup italics around names and parethesised translations)
	#(call munge,$(filter %.md,$^),apostrophize_names.pl,Use apostrophes when adding suffixes to proper names)
	$(call munge,$(filter %.md,$^),$(PANDOC) $(PANDOCARGS) $(PANDOCFILTERS) $(subst -smart,+smart,$(PANDOCFILTERARGS)),Normalize and tidy Markdown syntax using Pandoc)
	$(call munge,$(filter %.md,$^),reorder_punctuation.pl,Cleanup punctuation mark order such as footnote markers)

normalize_markdown: normalize_markdown_$(LANGUAGE)

.PHONY: normalize_markdown_en
normalize_markdown_en: $(filter en/%,$(MARKDOWNSOURCES)) ;

.PHONY: normalize_markdown_tr
normalize_markdown_tr: $(filter tr/%,$(MARKDOWNSOURCES))
	$(call munge,$(filter %.md,$^),ordinal_spaces.pl,Use narrow non-breaking spaces after ordinal numbers)

%.toc: %.pdf ;

%.tov: %.pdf ;

APPSOURCES := $(call pattern_list,$(SOURCES),.app)
.PHONY: $(APPSOURCES)
$(APPSOURCES): %.app: %-$(_app).info %.promotionals

WEBSOURCES := $(call pattern_list,$(SOURCES),.web)
.PHONY: $(WEBSOURCES)
$(WEBSOURCES): %.web: %-manifest.yml %.promotionals %.renderings

PLAYSOURCES := $(foreach ISBN,$(ISBNS),$(call isbntouid,$(ISBN)))

PHONYPLAYS := $(call pattern_list,$(PLAYSOURCES),.play)
.PHONY: $(PHONYPLAYS)
$(PHONYPLAYS): %.play: %_playbooks.csv
$(PHONYPLAYS): %.play: $$(call pattern_list,$$(call ebookisbn,$$*),.epub _frontcover.jpg _backcover.jpg)
$(PHONYPLAYS): %.play: $$(call pattern_list,$$(call printisbn,$$*),_interior.pdf _frontcover.jpg _backcover.jpg)

IGNORES += $(PLAYMETADATAS)
PLAYMETADATAS := $(call pattern_list,$(PLAYSOURCES),_playbooks.csv)
$(PLAYMETADATAS): %_playbooks.csv: $$(call pattern_list,$$(call ebookisbn,$$*) $$(call printisbn,$$*),_playbooks.json) %-bio.html %-description.html | $(require_pubdir)
	$(JQ) -M -e -s -r \
			--rawfile biohtml $(filter %-bio.html,$^) \
			--rawfile deshtml $(filter %-description.html,$^) \
			'[	"Identifier",
				"Enable for Sale?",
				"Title",
				"Subtitle",
				"Book Format",
				"Related Identifier [Format, Relationship], Semicolon-Separated",
				"Contributor [Role], Semicolon-Separated",
				"Biographical Note",
				"Subject Code [Schema], Semicolon-Separated",
				"Language",
				"Description",
				"Publication Date",
				"Page Count",
				"Series Name",
				"Volume in Series",
				"Buy Link",
				"On Sale Date",
				"TRY [Recommended Retail Price, Including Tax] Price",
				"Countries for TRY [Recommended Retail Price, Including Tax] Price"
			],
			(.[] | .[7] |= $$biohtml | .[10] |= $$deshtml | .[17] |= 0 | .[18] |= "WORLD")
			| map(. // "") | @csv' $(filter %_playbooks.json,$^) > $@
	$(addtopub)

ISBNMETADATAS := $(call pattern_list,$(ISBNS),_playbooks.json)
$(ISBNMETADATAS): %_playbooks.json: $$(call pattern_list,$$(call isbntouid,$$*)-,manifest.yml $(firstword $(LAYOUTS)).pdf)
	$(YQ) -M -e '
			([.identifier[] | select(.scheme == "ISBN-13").key] | length) as $$isbncount |
			(.lang | sub("tr"; "tur") | sub("en"; "eng")) as $$lang |
			(.date[] | select(."file-as" == "1\\. Basım").text | strptime("%Y-%m") | strftime("D:%Y-%m-01")) as $$date |
			([.creator[], .contributor[] | select (.role == "author").text + " [Author]", select (.role == "editor").text + " [Editor]", select (.role == "trl").text + " [Translator]"] | join("; ")) as $$contributors |
			(.identifier[] | select(.text == "$*").key) as $$format |
			[   "ISBN:$*",
				(if $$isbncount >= 2 and $$format == "paperback" then "No" else "Yes" end),
				.title,
				.subtitle,
				(if $$format == "paperback" then "Paperback" else "Digital" end),
				(if $$isbncount >= 2 then (.identifier[] | select(.key != $$format and .scheme == "ISBN-13") |
					(if .key == "ebook" then "ISBN:"+.text+" [Digital, Electronic version available as]" else "ISBN:"+.text+" [Paperback, Epublication based on]" end)) else "" end),
				$$contributors,
				"",
				([ .subjectcodes[] | .text + " [" + ."file-as" + "]" ] | join("; ")),
				$$lang,
				"",
				$$date,
				$(call pagecount,$(filter %.pdf,$^)),
				.seriestitle,
				(.seriestitle and .title as $$title | .seriestitles[] | select(.title == $$title).order),
				"$(call urlinfo,$(call isbntouid,$*))",
				$$date
			]' $(filter %-manifest.yml,$^) > $@

PLAYFRONTS := $(call pattern_list,$(ISBNS),_frontcover.jpg)
$(PLAYFRONTS): %_frontcover.jpg: $$(call isbntouid,$$*)-epub-$(_poster).jpg | $(require_pubdir)
	cp $< $@
	$(addtopub)

PLAYBACKS := $(call pattern_list,$(ISBNS),_backcover.jpg)
$(PLAYBACKS): %_backcover.jpg: %_frontcover.jpg | $(require_pubdir)
	cp $< $@
	$(addtopub)

PLAYINTS := $(call pattern_list,$(ISBNS),_interior.pdf)
$(PLAYINTS): %_interior.pdf: $$(call isbntouid,$$*)-$(firstword $(LAYOUTS))-$(_cropped).pdf | $(require_pubdir)
	$(PDFTK) $< cat 2-end output $@
	$(addtopub)

PLAYEPUBS := $(call pattern_list,$(ISBNS),.epub)
$(PLAYEPUBS): %.epub: $$(call isbntouid,$$*).epub | $(require_pubdir)
	$(EPUBCHECK) $<
	cp $< $@
	$(addtopub)

%-$(_app).pdf: %-$(_app)-$(_print).pdf | $(require_pubdir)
	cp $< $@
	$(addtopub)
	rm -f $(PUBDIR)/$<

%-$(_app).info: %-$(_app)-$(_print).toc %-$(_app)-$(_print).pdf %-manifest.yml | $(require_pubdir)
	$(CASILEDIR)scripts/toc2breaks.lua $* $(filter %-$(_app)-$(_print).toc,$^) $(filter %-manifest.yml,$^) $@ |
		while read range out; do
			$(PDFTK) $(filter %-$(_app)-$(_print).pdf,$^) cat $$range output $$out
			ln -f $$out $(PUBDIR)/$$out
		done
	$(addtopub)

$(_issue).info: | $(require_pubdir)
	for source in $(SOURCES); do
		echo -e "# $$source\n"
		if test -d $${source}-bolumler; then
			$(FIND) $${source}-bolumler -name '*.md' -print |
				$(SORT) -n |
				while read chapter; do
					number=$${chapter%-*}; number=$${number#*/}
					$(SED) -ne "/^# /{s/ {.*}$$//;s!^# *\(.*\)! - [ ] $$number — [\1]($$chapter)!g;p}" $$chapter
				done
		elif $(GREP) -q '^# ' $$source.md; then
			$(SED) -ne "/^# /{s/^# *\(.*\)/ - [ ] [\1]($${source}.md)/g;p}" $$source.md
		else
			echo -e " - [ ] [$${source}]($${source}.md)"
		fi
		echo
	done > $@
	$(addtopub)

COVERBACKGROUNDS := $(call pattern_list,$(SOURCES),$(UNBOUNDLAYOUTS),-$(_cover)-$(_background).png)
git_background = $(shell $(GIT) ls-files -- $(call strip_layout,$1) 2> /dev/null)
$(COVERBACKGROUNDS): %-$(_cover)-$(_background).png: $$(call git_background,$$@) $$(geometryfile)
	$(sourcegeometry)
	$(if $(filter %.png,$(call git_background,$@)),true,false) && $(MAGICK) \
		$(MAGICKARGS) \
		$(filter %.png,$^) \
		-gravity $(COVERGRAVITY) \
		-extent  "%[fx:w/h>=$${pageaspect}?h*$${pageaspect}:w]x" \
		-extent "x%[fx:w/h<=$${pageaspect}?w/$${pageaspect}:h]" \
		-resize $${pagewpx}x$${pagehpx} \
		$(call magick_background_filter) \
		$@ ||:
	$(if $(filter %.png,$(call git_background,$@)),false,true) && $(MAGICK) \
		$(MAGICKARGS) \
		-size $${pagewpx}x$${pagehpx}^ $(call magick_background_cover) \
		$@ ||:

# Requires fake geometry file with no binding spec because binding not part of pattern
%-$(_poster).png: %-$(_print)-$(_cover).png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-resize $${pagewpp}x$${pagehpp}^ \
		$(and $(filter epub,$(call parse_papersize,$@)),-resize 1000x1600^) \
		$@

COVERIMAGES := $(call pattern_list,$(SOURCES),$(UNBOUNDLAYOUTS),-$(_cover).png)
$(COVERIMAGES): %-$(_cover).png: %-$(_cover)-$(_background).png %-$(_cover)-$(_fragment).png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-compose SrcOver \
		\( -background none \
			-gravity Center \
			-size $${pagewpx}x$${pagehpx} \
			xc: \
			$(call magick_cover) \
		\) -composite \
		\( \
			-gravity Center \
			$*-$(_cover)-$(_fragment).png \
		\) -compose SrcOver -composite \
		-gravity Center \
		-size '%[fx:u.w]x%[fx:u.h]' \
		$@

# Gitlab projects need a sub 200kb icon image
%-icon.png: %-$(_square)-$(_poster).png | $(require_pubdir)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-define png:extent=200kb \
		-resize 196x196 \
		-quality 9 \
		$@
	$(addtopub)

COVERPDFS := $(call pattern_list,$(SOURCES),$(UNBOUNDLAYOUTS),-$(_cover).pdf)
$(COVERPDFS): %-$(_cover).pdf: %-$(_cover).png %-$(_cover)-$(_text).pdf
	$(COVERS) || exit 0
	text=$$(mktemp kapakXXXXXX.pdf)
	bg=$$(mktemp kapakXXXXXX.pdf)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-density $(LODPI) \
		-compress jpeg \
		-quality 50 \
		+repage \
		$${bg}
	$(PDFTK) $(filter %.pdf,$^) cat 1 output $${text}
	$(PDFTK) $${text} background $${bg} output $@
	rm $${text} $${bg}

BINDINGFRAGMENTS := $(call pattern_list,$(SOURCES),$(BOUNDLAYOUTS),-$(_binding)-$(_text).pdf)
$(BINDINGFRAGMENTS): %-$(_binding)-$(_text).pdf: $(CASILEDIR)binding.xml $$(call parse_bookid,$$@)-manifest.yml $(LUAINCLUDES) $$(subst -$(_binding)-$(_text),,$$@) | $$(TARGETLUAS_$$(call parse_bookid,$$@)) $(PROJECTLUA) $(CASILEDIR)layouts/$$(call unlocalize,$$(call parse_papersize,$$@)).lua $(LUALIBS)
	cat <<- EOF > $*.lua
		versioninfo = "$(call versioninfo,$@)"
		metadatafile = "$(filter %-manifest.yml,$^)"
		spine = "$(call spinemm,$(filter %.pdf,$^))mm"
		$(foreach LUA,$(call reverse,$|),
		SILE.require("$(basename $(LUA))"))
	EOF
	export SILE_PATH="$(subst $( ),;,$(SILEPATH))"
	$(SILE) $(SILEFLAGS) -I <(echo "CASILE.include = '$*'") $< -o $@

FRONTFRAGMENTS := $(call pattern_list,$(SOURCES),$(BOUNDLAYOUTS),-$(_binding)-$(_fragment)-$(_front).png)
$(FRONTFRAGMENTS): %-$(_fragment)-$(_front).png: %-$(_text).pdf
	$(MAGICK) \
		$(MAGICKARGS) \
		-density $(HIDPI) \
		"$<[0]" \
		-colorspace sRGB \
		$(call magick_fragment_front) +repage \
		-compose Copy -layers Flatten +repage \
		$@

BACKFRAGMENTS := $(call pattern_list,$(SOURCES),$(BOUNDLAYOUTS),-$(_binding)-$(_fragment)-$(_back).png)
$(BACKFRAGMENTS): %-$(_fragment)-$(_back).png: %-$(_text).pdf
	$(MAGICK) \
		$(MAGICKARGS) \
		-density $(HIDPI) \
		"$<[1]" \
		-colorspace sRGB \
		$(call magick_fragment_back) +repage \
		-compose Copy -layers Flatten +repage \
		$@

SPINEFRAGMENTS := $(call pattern_list,$(SOURCES),$(BOUNDLAYOUTS),-$(_binding)-$(_fragment)-$(_spine).png)
$(SPINEFRAGMENTS): %-$(_fragment)-$(_spine).png: %-$(_text).pdf | $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		-density $(HIDPI) \
		"$<[2]" \
		-colorspace sRGB \
		-crop $${spinepx}x+0+0 +repage \
		$(call magick_fragment_spine) \
		-compose Copy -layers Flatten +repage \
		$@

COVERFRAGMENTS := $(call pattern_list,$(SOURCES),$(UNBOUNDLAYOUTS),-$(_cover)-$(_text).pdf)
$(COVERFRAGMENTS): %-$(_text).pdf: $(CASILEDIR)cover.xml $$(call parse_bookid,$$@)-manifest.yml $(LUAINCLUDES) | $$(TARGETLUAS_$$(call parse_bookid,$$@)) $(PROJECTLUA) $(CASILEDIR)layouts/$$(call unlocalize,$$(call parse_papersize,$$@)).lua $(LUALIBS)
	cat <<- EOF > $*.lua
		versioninfo = "$(call versioninfo,$@)"
		metadatafile = "$(filter %-manifest.yml,$^)"
		$(foreach LUA,$(call reverse,$|),
		SILE.require("$(basename $(LUA))"))
	EOF
	export SILE_PATH="$(subst $( ),;,$(SILEPATH))"
	$(SILE) $(SILEFLAGS) -I <(echo "CASILE.include = '$*'") $< -o $@

FRONTFRAGMENTIMAGES := $(call pattern_list,$(SOURCES),$(UNBOUNDLAYOUTS),-$(_cover)-$(_fragment).png)
$(FRONTFRAGMENTIMAGES): %-$(_fragment).png: %-$(_text).pdf
	$(MAGICK) \
		$(MAGICKARGS) \
		-density $(HIDPI) \
		"$<[0]" \
		-colorspace sRGB \
		$(call magick_fragment_cover) \
		-compose Copy -layers Flatten +repage \
		$@

INTERMEDIATES += publisher_emblum.svg publisher_emblum-grey.svg publisher_logo.svg publisher_logo-grey.svg

PUBLISHEREMBLUM ?= $(PUBLISHERDIR)/emblum.svg
publisher_emblum.svg: $(PUBLISHEREMBLUM)
	$(call skip_if_tracked,$@)
	cp $< $@

publisher_emblum-grey.svg: $(PUBLISHEREMBLUM)
	$(call skip_if_tracked,$@)
	cp $< $@

PUBLISHERLOGO ?= $(PUBLISHERDIR)/logo.svg
publisher_logo.svg: $(PUBLISHERLOGO)
	$(call skip_if_tracked,$@)
	cp $< $@

publisher_logo-grey.svg: $(PUBLISHERLOGO)
	$(call skip_if_tracked,$@)
	cp $< $@

BINDINGIMAGES := $(call pattern_list,$(SOURCES),$(BOUNDLAYOUTS),-$(_binding).png)
$(BINDINGIMAGES): %-$(_binding).png: $$(basename $$@)-$(_fragment)-$(_front).png $$(basename $$@)-$(_fragment)-$(_back).png $$(basename $$@)-$(_fragment)-$(_spine).png $$(call parse_bookid,$$@)-$(_barcode).png publisher_emblum.svg publisher_emblum-grey.svg publisher_logo.svg publisher_logo-grey.svg $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		-size $${imgwpx}x$${imghpx} -density $(HIDPI) \
		$(or $(and $(call git_background,$*-$(_cover)-$(_background).png),$(call git_background,$*-$(_cover)-$(_background).png) -resize $${imgwpx}x$${imghpx}!),$(call magick_background_binding)) \
		$(call magick_border) \
		-compose SrcOver \( -gravity East -size $${pagewpx}x$${pagehpx} -background none xc: $(call magick_front) -splice $${bleedpx}x \) -composite \
		-compose SrcOver \( -gravity West -size $${pagewpx}x$${pagehpx} -background none xc: $(call magick_back) -splice $${bleedpx}x \) -composite \
		-compose SrcOver \( -gravity Center -size $${spinepx}x$${pagehpx} -background none xc: $(call magick_spine) \) -composite \
		\( -gravity East $(filter %-$(_front).png,$^) -splice $${bleedpx}x -write mpr:text-front \) -compose SrcOver -composite \
		\( -gravity West $(filter %-$(_back).png,$^) -splice $${bleedpx}x -write mpr:text-front \) -compose SrcOver -composite \
		\( -gravity Center $(filter %-$(_spine).png,$^) -write mpr:text-front \) -compose SrcOver -composite \
		$(call magick_emblum,publisher_emblum.svg) \
		$(call magick_barcode,$(filter %-$(_barcode).png,$^)) \
		$(call magick_logo,publisher_logo.svg) \
		-gravity Center -size '%[fx:u.w]x%[fx:u.h]' \
		-compose SrcOver -composite \
		$(call magick_binding) \
		$@

%-printcolor.png: %.png
	$(MAGICK) \
		$(MAGICKARGS) \
		$< $(call magick_printcolor) \
		$@

%-$(_binding).svg: $(CASILEDIR)binding.svg $$(basename $$@)-printcolor.png $$(geometryfile)
	$(sourcegeometry)
	ver=$(subst @,\\@,$(call versioninfo,$@))
	$(PERL) $(PERLARGS) -pne "
			s#IMG#$(filter %.png,$^)#g;
			s#VER#$${ver}#g;
			s#CANVASX#$${bindingwmm}mm#g;
			s#CANVASY#$${pagehmm}mm#g;
			s#IMW#$${imgwpm}#g;
			s#IMH#$${imghpm}#g;
			s#WWW#$${bindingwpm}#g;
			s#HHH#$${pagehpm}#g;
			s#BLEED#$${bleedpm}#g;
			s#TRIM#$${trimpm}#g;
			s#CW#$${pagewpm}#g;
			s#SW#$${spinepm}#g;
		" $< > $@

%-$(_binding).pdf: %-$(_binding).svg $$(geometryfile) | $(require_pubdir)
	$(sourcegeometry)
	$(INKSCAPE) --without-gui \
		--export-dpi=$${hidpi} \
		--export-area-page \
		--export-margin=$${trimmm} \
		--file=$< \
		--export-pdf=$@
	$(addtopub)

# Dial down trim/bleed for non-full-bleed output so we can use the same math
UNBOUNDGEOMETRIES := $(call pattern_list,$(SOURCES),$(UNBOUNDLAYOUTS),-$(_geometry).sh)
$(UNBOUNDGEOMETRIES): private BLEED = $(NOBLEED)
$(UNBOUNDGEOMETRIES): private TRIM = $(NOTRIM)

# Some output formats don't have PDF content, but we still need to calculate the
# page geometry, so generate a single page PDF to measure with no binding scenario
EMPTYGEOMETRIES := $(call pattern_list,$(_geometry),$(PAPERSIZES),.pdf)
$(EMPTYGEOMETRIES): $(_geometry)-%.pdf: $(CASILEDIR)geometry.xml $(LUAINCLUDES)
	export SILE_PATH="$(subst $( ),;,$(SILEPATH))"
	$(SILE) $(SILEFLAGS) \
		-e "papersize = '$(call unlocalize,$*)'" \
		$< -o $@

IGNORES += $(EMPTYGEOMETRIES)

# Hard coded list instead of plain pattern because make is stupid: http://stackoverflow.com/q/41694704/313192
GEOMETRIES := $(call pattern_list,$(SOURCES),$(ALLLAYOUTS),-$(_geometry).sh)
$(GEOMETRIES): %-$(_geometry).sh: $$(call geometrybase,$$@) $$(call newgeometry,$$@)
	$(ZSH) << 'EOF' # inception to break out of CaSILE's make shell wrapper
	export PS4=; set -x ; exec 2> $@ # black magic to output the finished math
	hidpi=$(HIDPI)
	lodpi=$(HIDPI)
	bleedmm=$(BLEED)
	bleedpx=$(call mmtopx,$(BLEED))
	bleedpm=$(call mmtopm,$(BLEED))
	bleedpt=$(call mmtopt,$(BLEED))
	trimmm=$(TRIM)
	trimpx=$(call mmtopx,$(TRIM))
	trimpm=$(call mmtopm,$(TRIM))
	trimpt=$(call mmtopt,$(TRIM))
	$(shell $(MAGICK) identify -density $(HIDPI) -format '
			pagewmm=%[fx:round(w/$(HIDPI)*25.399986)]
			pagewpx=%[fx:w]
			pagewpm=%[fx:round(w/$(HIDPI)*90)]
			pagewpt=%[fx:round(w/$(HIDPI)*72)]
			pagewpp=%[fx:round(w/$(HIDPI)*$(LODPI))]
			pagehmm=%[fx:round(h/$(HIDPI)*25.399986)]
			pagehpx=%[fx:h]
			pagehpm=%[fx:round(h/$(HIDPI)*90)]
			pagehpt=%[fx:round(h/$(HIDPI)*72)]
			pagehpp=%[fx:round(h/$(HIDPI)*$(LODPI))]
			pageaspect=%[fx:w/h]
		' "$(filter $(_geometry)-%.pdf,$^)[0]" || echo false)
	pminpx=$$(($$pagewpx<$$pagehpx?$$pagewpx:$$pagehpx))
	pmaxpx=$$(($$pagewpx>$$pagehpx?$$pagewpx:$$pagehpx))
	pagecount=$(call pagecount,$(filter %.pdf,$<))
	spinemm=$(call spinemm,$(filter %.pdf,$<))
	spinepx=$(call mmtopx,$(call spinemm,$(filter %.pdf,$<)))
	spinepm=$(call mmtopm,$(call spinemm,$(filter %.pdf,$<)))
	spinept=$(call mmtopt,$(call spinemm,$(filter %.pdf,$<)))
	fbwmm=$$(($$pagewmm+$$bleedmm))
	fbwpx=$$(($$pagewpx+$$bleedpx))
	fbwpm=$$(($$pagewpm+$$bleedpm))
	fbwpt=$$(($$pagewpt+$$bleedpt))
	ftwmm=$$(($$pagewmm+$$trimmm*2))
	ftwpx=$$(($$pagewpx+$$trimpx*2))
	ftwpm=$$(($$pagewpm+$$trimpm*2))
	ftwpt=$$(($$pagewpt+$$trimpt*2))
	fthmm=$$(($$pagehmm+$$trimmm*2))
	fthpx=$$(($$pagehpx+$$trimpx*2))
	fthpm=$$(($$pagehpm+$$trimpm*2))
	fthpt=$$(($$pagehpt+$$trimpt*2))
	bindingwmm=$$(($$pagewmm+$$spinemm+$$pagewmm))
	bindingwpx=$$(($$pagewpx+$$spinepx+$$pagewpx))
	bindingwpm=$$(($$pagewpm+$$spinepm+$$pagewpm))
	bindingwpt=$$(($$pagewpt+$$spinept+$$pagewpt))
	imgwmm=$$(($$bindingwmm+$$bleedmm*2))
	imgwpx=$$(($$bindingwpx+$$bleedpx*2))
	imgwpm=$$(($$bindingwpm+$$bleedpm*2))
	imgwpt=$$(($$bindingwpt+$$bleedpt*2))
	imghmm=$$(($$pagehmm+$$bleedmm*2))
	imghpx=$$(($$pagehpx+$$bleedpx*2))
	imghpm=$$(($$pagehpm+$$bleedpm*2))
	imghpt=$$(($$pagehpt+$$bleedpt*2))
	widelayout=$$(($${pagewpx} > $${pagehpx}))
	$(call geometry_extras)
	EOF

%-$(_binding)-$(_front).png: %-$(_binding).png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-gravity East \
		-crop $${pagewpx}x$${pagehpx}+$${bleedpx}+0! \
		$@

%-$(_binding)-$(_back).png: %-$(_binding).png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-gravity West \
		-crop $${pagewpx}x$${pagehpx}+$${bleedpx}+0! \
		$@

%-$(_binding)-$(_spine).png: %-$(_binding).png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-gravity Center \
		-crop $${spinepx}x$${pagehpx}+0+0! \
		$@

%-$(_print)-pov-$(_front).png: %-$(_print).pdf $$(geometryfile)
	$(sourcegeometry)
	$(call pagetopng,1)

%-$(_print)-pov-$(_back).png: %-$(_print).pdf $$(geometryfile)
	$(sourcegeometry)
	$(call pagetopng,$(call pagecount,$<))

%-$(_print)-pov-$(_spine).png: $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		-size $${pagewpx}x$${pagehpx} \
		xc:none \
		$@

%-pov-$(_front).png: %-$(_binding)-printcolor.png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-gravity East \
		-crop $${pagewpx}x$${pagehpx}+$${bleedpx}+0! \
		$(call magick_emulateprint) \
		$(and $(filter $(_paperback),$(call parse_binding,$@)),$(call magick_crease,0+)) \
		$(call magick_fray) \
		$@

%-pov-$(_back).png: %-$(_binding)-printcolor.png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-gravity West -crop $${pagewpx}x$${pagehpx}+$${bleedpx}+0! \
		$(call magick_emulateprint) \
		$(and $(filter $(_paperback),$(call parse_binding,$@)),$(call magick_crease,w-)) \
		$(call magick_fray) \
		$@

%-pov-$(_spine).png: %-$(_binding)-printcolor.png $$(geometryfile)
	$(sourcegeometry)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-gravity Center \
		-crop $${spinepx}x$${pagehpx}+0+0! \
		-extent 200%x100% \
		$(call magick_emulateprint) \
		$@

BOOKSCENESINC := $(call pattern_list,$(SOURCES),$(RENDERED),.inc)
$(BOOKSCENESINC): %.inc: $$(geometryfile) %-pov-$(_front).png %-pov-$(_back).png %-pov-$(_spine).png
	$(sourcegeometry)
	cat <<- EOF > $@
		#declare FrontImg = "$(filter %-pov-$(_front).png,$^)";
		#declare BackImg = "$(filter %-pov-$(_back).png,$^)";
		#declare SpineImg = "$(filter %-pov-$(_spine).png,$^)";
		#declare BindingType = "$(call unlocalize,$(call parse_binding,$@))";
		#declare StapleCount = $(STAPLECOUNT);
		#declare CoilSpacing = $(COILSPACING);
		#declare CoilWidth = $(COILWIDTH);
		#declare CoilColor = $(COILCOLOR);
		#declare PaperWeight = $(PAPERWEIGHT);
		#declare BookThickness = $${spinemm} / $${pagewmm} / 2;
		#declare HalfThick = BookThickness / 2;
	EOF

BOOKSCENES := $(call pattern_list,$(SOURCES),$(RENDERED),-$(_3d).pov)
$(BOOKSCENES): %-$(_3d).pov: $$(geometryfile) %.inc
	$(sourcegeometry)
	cat <<- EOF > $@
		#declare DefaultBook = "$(filter %.inc,$^)";
		#declare Lights = $(call scale,8,2);
		#declare BookAspect = $${pagewmm} / $${pagehmm};
		#declare BookThickness = $${spinemm} / $${pagewmm} / 2;
		#declare HalfThick = BookThickness / 2;
		#declare toMM = 1 / $${pagehmm};
	EOF

ifneq ($(strip $(SOURCES)),$(strip $(PROJECT)))
SERIESSCENES := $(call pattern_list,$(PROJECT),$(RENDERED),-$(_3d).pov)
$(SERIESSCENES): $(PROJECT)-%-$(_3d).pov: $(firstword $(SOURCES))-%-$(_3d).pov $(call pattern_list,$(SOURCES),-%.inc)
	cat <<- EOF > $@
		#include "$<"
		#declare BookCount = $(words $(TARGETS));
		#declare Books = array[BookCount] {
		$(subst $(space),$(,)
		,$(foreach INC,$(call series_sort,$(filter %.inc,$^)),"$(INC)")) }
	EOF
endif

%-$(_light).png: private SCENELIGHT = rgb<1,1,1>
%-$(_dark).png:  private SCENELIGHT = rgb<0,0,0>

%-$(_3d)-$(_front)-$(_light).png: $(CASILEDIR)book.pov %-$(_3d).pov $(CASILEDIR)front.pov
	$(call povray,$(filter %/book.pov,$^),$*-$(_3d).pov,$(filter %/front.pov,$^),$@,$(SCENEX),$(SCENEY))

%-$(_3d)-$(_front)-$(_dark).png: $(CASILEDIR)book.pov %-$(_3d).pov $(CASILEDIR)front.pov
	$(call povray,$(filter %/book.pov,$^),$*-$(_3d).pov,$(filter %/front.pov,$^),$@,$(SCENEX),$(SCENEY))

%-$(_3d)-$(_back)-$(_light).png: $(CASILEDIR)book.pov %-$(_3d).pov $(CASILEDIR)back.pov
	$(call povray,$(filter %/book.pov,$^),$*-$(_3d).pov,$(filter %/back.pov,$^),$@,$(SCENEX),$(SCENEY))

%-$(_3d)-$(_back)-$(_dark).png: $(CASILEDIR)book.pov %-$(_3d).pov $(CASILEDIR)back.pov
	$(call povray,$(filter %/book.pov,$^),$*-$(_3d).pov,$(filter %/back.pov,$^),$@,$(SCENEX),$(SCENEY))

%-$(_3d)-$(_pile)-$(_light).png: $(CASILEDIR)book.pov %-$(_3d).pov $(CASILEDIR)pile.pov
	$(call povray,$(filter %/book.pov,$^),$*-$(_3d).pov,$(filter %/pile.pov,$^),$@,$(SCENEY),$(SCENEX))

%-$(_3d)-$(_pile)-$(_dark).png: $(CASILEDIR)book.pov %-$(_3d).pov $(CASILEDIR)pile.pov
	$(call povray,$(filter %/book.pov,$^),$*-$(_3d).pov,$(filter %/pile.pov,$^),$@,$(SCENEY),$(SCENEX))

$(PROJECT)-%-$(_3d)-$(_montage)-$(_light).png: $(CASILEDIR)book.pov $(PROJECT)-%-$(_3d).pov $(CASILEDIR)montage.pov
	$(call povray,$(filter %/book.pov,$^),$(filter %-$(_3d).pov,$^),$(filter %/montage.pov,$^),$@,$(SCENEY),$(SCENEX))

$(PROJECT)-%-$(_3d)-$(_montage)-$(_dark).png: $(CASILEDIR)book.pov $(PROJECT)-%-$(_3d).pov $(CASILEDIR)montage.pov
	$(call povray,$(filter %/book.pov,$^),$(filter %-$(_3d).pov,$^),$(filter %/montage.pov,$^),$@,$(SCENEY),$(SCENEX))

# Combine black / white background renderings into transparent one with shadows
%.png: %-$(_dark).png %-$(_light).png | $(require_pubdir)
	$(MAGICK) \
		$(MAGICKARGS) \
		$(filter %.png,$^) \
		-alpha Off \
		\( -clone 0,1 -compose Difference -composite -negate \) \
		\( -clone 0,2 +swap -compose Divide -composite \) \
		-delete 0,1 +swap -compose CopyOpacity -composite \
		-compose Copy -alpha On -layers Flatten +repage \
		-channel Alpha -fx 'a > 0.5 ? 1 : a' -channel All \
		$(call pov_crop,$(if $(findstring $(_pile),$*),$(SCENEY)x$(SCENEX),$(SCENEX)x$(SCENEY))) \
		$@
	$(addtopub)

%.jpg: %.png | $(require_pubdir)
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-background '$(call povtomagick,$(SCENELIGHT))' \
		-alpha Remove \
		-alpha Off \
		-quality 85 \
		$@
	$(addtopub)

%-epub-metadata.yml: %-manifest.yml %-epub-$(_poster).jpg
	echo '---' > $@
	$(YQ) -M -e -y '{title: [ { type: "main", text: .title  }, { type: "subtitle", text: .subtitle } ], creator: .creator, contributor: .contributor, identifier: .identifier, date: .date | last | .text, published: .date | first | .text, lang: .lang, description: .abstract, rights: .rights, publisher: .publisher, source: (if .source then (.source[]? | select(.type == "title").text) else null end), "cover-image": "$(filter %.jpg,$^)" }' < $< >> $@
	echo '...' >> $@

%.epub: private PANDOCFILTERS += --lua-filter=$(CASILEDIR)pandoc-filters/epubclean.lua
%.epub: %-$(_processed).md %-epub-metadata.yml | $(require_pubdir)
	$(PANDOC) \
		$(PANDOCARGS) \
		$(PANDOCFILTERS) \
		$*-epub-metadata.yml \
		$*-$(_processed).md -o $@
	$(addtopub)

%.odt: %-$(_processed).md %-manifest.yml | $(require_pubdir)
	$(PANDOC) \
		$(PANDOCARGS) \
		$(PANDOCFILTERS) \
		$*-manifest.yml \
		$*-$(_processed).md -o $@
	$(addtopub)

%.docx: %-$(_processed).md %-manifest.yml | $(require_pubdir)
	$(PANDOC) \
		$(PANDOCARGS) \
		$(PANDOCFILTERS) \
		$*-manifest.yml \
		$*-$(_processed).md -o $@
	$(addtopub)

%.mobi: %.epub | $(require_pubdir)
	$(KINDLEGEN) $< ||:
	$(addtopub)

PHONYSCREENS := $(call pattern_list,$(SOURCES),.$(_screen))
.PHONY: $(PHONYSCREENS)
$(PHONYSCREENS): %.$(_screen): %-$(_screen).pdf %-manifest.yml

MANIFESTS := $(call pattern_list,$(SOURCES),-manifest.yml)
$(MANIFESTS): %-manifest.yml: $(CASILEDIR)casile.yml $(METADATA) $(PROJECTYAML) $$(TARGETYAMLS_$$*) | $(require_pubdir)
	# $(YQ) -M -e -s -y 'reduce .[] as $$item({}; . + $$item)' $(filter %.yml,$^) |
	$(PERL) -MYAML::Merge::Simple=merge_files -MYAML -E 'say Dump merge_files(@ARGV)' $(filter %.yml,$^) |
		$(SED) -e 's/~$$/nil/g;/^--- |/d;$$a...' \
			-e '/text: [[:digit:]]\{10,13\}/{p;s/^\([[:space:]]*\)text: \([[:digit:]]\+\)$$/$(PYTHON) -c "import isbnlib; print(\\"\1mask: \\" + isbnlib.mask(\\"\2\\"))"/e}' \
			-e '/\(own\|next\)cloudshare: [^"]/s/: \(.*\)$$/: "\1"/' > $@
	$(addtopub)

INTERMEDIATES += *.html

BIOHTMLS := $(call pattern_list,$(SOURCES),-bio.html)
$(BIOHTMLS): %-bio.html: %-manifest.yml
	$(YQ) -r '.creator[0].about' $(filter %-manifest.yml,$^) |
		$(PANDOC) -f markdown -t html | head -c -1 > $@

DESHTMLS := $(call pattern_list,$(SOURCES),-description.html)
$(DESHTMLS): %-description.html: %-manifest.yml
	$(YQ) -r '.abstract' $(filter %-manifest.yml,$^) |
		$(PANDOC) -f markdown -t html | head -c -1 > $@

INTERMEDIATES += *-url.*

%-url.png: %-url.svg
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-bordercolor white -border 10x10 \
		-bordercolor black -border 4x4 \
		$@

%-url.svg:
	$(ZINT) \
			--direct \
			--filetype=svg \
			--scale=10 \
			--barcode=58 \
			--data="$(call urlinfo,$@)" \
		> $@

INTERMEDIATES += *-$(_barcode).*

%-$(_barcode).svg: %-manifest.yml
	$(ZINT) --direct \
			--filetype=svg \
			--scale=5 \
			--barcode=69 \
			--height=30 \
			--data=$(shell $(CASILEDIR)scripts/isbn_format.py $< paperback) |\
		$(SED) -e 's/Helvetica\( Regular\)\?/TeX Gyre Heros/g' \
		> $@

%-$(_barcode).png: %-$(_barcode).svg
	$(MAGICK) \
		$(MAGICKARGS) \
		$< \
		-bordercolor white -border 10 \
		-font Hack-Regular -pointsize 36 \
		label:"ISBN $(shell $(CASILEDIR)scripts/isbn_format.py $*-manifest.yml paperback mask)" +swap -gravity Center -append \
		-bordercolor white -border 0x10 \
		-resize $(call scale,1200)x \
		$@
	if [[ $(shell $(CASILEDIR)scripts/isbn_format.py $*-manifest.yml paperback) == 9786056644504 ]]; then
		$(MAGICK) \
			$(MAGICKARGS) \
			$@ \
			-stroke red \
			-strokewidth $(call scale,10) \
			-draw 'line 0,0,%[fx:w],%[fx:h]' \
			$@
	fi

STATSSOURCES := $(call pattern_list,$(SOURCES),-stats)

.PHONY: stats
stats: $(STATSSOURCES)

.PHONY: $(STATSSOURCES)
$(STATSSOURCES): %-stats:
	stats.zsh $* $(STATSMONTHS)

repository-lastcommit.ts: $$(newcommits)
	touch -d $$($(GIT) log -n1 --format=%cI) $@

repository-worklog.sqlite: $(CASILEDIR)scripts/worklog.zsh repository-lastcommit.ts
	$(SQLITE3) $@ 'DROP TABLE IF EXISTS commits; CREATE TABLE commits (sha TEXT, author TEXT, date DATE, file TEXT, added INT, removed INT)'
	$< | $(SQLITE3) -batch $@

WORKLOGFIELDS := sha AS 'Commit', date AS 'Date', file AS 'Filename', added AS 'Added', removed AS 'Removed'

repository-worklog.md: repository-worklog.sqlite force
	now=$$(LANG=en_US date +%c)
	ver=$(call versioninfo,$(PROJECT))
	export IFS='|'
	$(SQLITE3) $< "SELECT DISTINCT(author) FROM commits" |
		while read author; do
			$(SQLITE3) $< "SELECT DISTINCT strftime('%Y-%m', date) FROM commits WHERE author='$${author}'" |
				while read month; do
					$(SQLITE3) repository-worklog.sqlite "SELECT SUM(added+ -removed) FROM commits WHERE author='$${author}' and strftime('%Y-%m', date)='$${month}'" | read netadded
					[[ $${netadded} -ge 1 ]] || continue
					echo "# Worklog for $${author}"
					echo "## $$(LANG=en_US date +'%B %Y' -d $${month}-01)"
					echo
					echo "Report Generated on $${now} from repository $${ver}."
					echo
					echo "### File Edits"
					echo
					echo "Net characters added: $${netadded}"
					echo
					echo '``` table'
					echo '---\nheader: True\n---'
					$(SQLITE3) --header -csv repository-worklog.sqlite "SELECT $(WORKLOGFIELDS) FROM commits WHERE author='$${author}' AND strftime('%Y-%m', date)='$${month}'"
					echo '```'
					echo
				done
		done |
			$(PANDOC) $(PANDOCARGS) -F pantable -o $@

repository-worklog.pdf: repository-worklog.md
	$(PANDOC) $(PANDOCARGS) \
		-t latex \
		--pdf-engine=xelatex \
		-V "mainfont:Libertinus Serif" \
		-V "geometry:landscape" \
		$< -o $@

%-$(_verses).json: %-$(_processed).md
	$(if $(HEAD),head -n$(HEAD),cat) $< |
		extract_references.js > $@

%-$(_verses)-$(_sorted).json: %-$(_verses).json
	$(JQ) -M -e 'unique_by(.osis) | sort_by(.seq)' $< > $@

%-$(_verses)-$(_text).yml: %-$(_verses)-$(_sorted).json
	$(JQ) -M -e -r 'map_values(.osis) | _nwise(100) | join(";")' $< |
		$(XARGS) -n1 -iX curl -s -L "https://sahneleme.incil.info/api/X" |
		# Because yq doesn't --slurp JSON, see https://github.com/kislyuk/yq/issues/56
		$(JQ) -s '[.]' | $(YQ) -M -e -y ".[0][] | map_values(.scripture)" |
		$(GREP) -v '^---$$' |
		# Because lua-yaml has a bug parsing non quoted keys...
		$(SED) -e '/^[^ ]/s/^\([^:]\+\):/"\1":/' \
			> $@

.PHONY: normalize_references
normalize_references: $(MARKDOWNSOURCES)
	$(call munge,$^,normalize_references.js,Normalize verse references using BCV parser)

.PHONY: normalize
normalize: normalize_lua normalize_markdown normalize_references

split_chapters:
	$(if $(MARKDOWNSOURCES),,exit 0)
	$(foreach SOURCE,$(MARKDOWNSOURCES),$(call split_chapters,$(SOURCE)))

normalize_files: private PANDOCFILTERS = --lua-filter=$(CASILEDIR)pandoc-filters/chapterid.lua
normalize_files: $(CASILEDIR)pandoc-filters/chapterid.lua
	$(GIT) diff-index --quiet --cached HEAD || exit 1 # die if anything already staged
	$(if $(MARKDOWNSOURCES),,exit 0)
	echo $(MARKDOWNSOURCES) |
		$(PERL) -pne 's/ /\n/g' |
		$(PCREGREP) "$(PROJECTDIR)/($(subst $(space),|,$(strip $(SOURCES))))-.*/" |
		while read src; do
			$(GIT) diff-files --quiet -- $${src} || exit 1 # die if this file has uncommitted changes
			basename $${src} | $(PERL) -pne 's/-.*$$//' | read chapno
			dirname $${src} | read dir
			$(SED) -n '/^#/{s/ı/i/g;p}' $${src} |
				$(PANDOC) $(PANDOCARGS) $(PANDOCFILTERS) $(PANDOCFILTERARGS) | read identifier
				target="$${dir}/$${chapno}-$${identifier}.md"
				[[ $${src} == $${target} ]] || $(GIT) mv "$${src}" "$${target}"
		done
	$(GIT) diff-index --quiet --cached HEAD || $(GIT) commit -m "[auto] Normalize filenames based on chapter ids"

watch:
	$(GIT) ls-files --recurse-submodules |
		$(ENTR) $(ENTRFLAGS) make DRAFT=true LAZY=true $(WATCHARGS)

diff:
	$(GIT) diff --color=always --ignore-submodules --no-ext-diff
	$(GIT) submodule foreach $(GIT) diff --color=always --no-ext-diff

-include $(POSTCASILEINCLUDE)
