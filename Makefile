
# -*- indent-with-tabs: 1 
# Simple makefile which mostly encapsulates setup.py invocations.  Useful as
# much as documentation as it is for invocation.

#svnrev	:= $(shell svn info | grep ^Revision | awk '{print $$2}' )

# This is needed to avoid randomised order of html element attributes under
# py27 - py35.  For py36 and later, dictionary key order is insertion order,
# so the test masters for lxml-generated html output have to be different for
# python 3 versions 3.6 and higher, compared to 2.7 - 3.5

# Regarding PDF testing: This is mainly done when running test.py, which not
# only generates a test PDF file, but deconstructs it and looks at some of
# the content.  Generating PDF files for each input file and just making
# binary comparisons is prone to false negatives, so in general there's no
# PDF file generation below.

export PYTHONHASHSEED = 0

datetime_regex = [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T_ ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]
version_regex =  [Vv]ersion [2N]\(\.[0-9N]\+\)\+\(\.dev\)\?
date_regex = [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]
generator_regex = name="generator"

py = $(shell python -c 'import sys; print("py%s%s" %(sys.version_info.major,sys.version_info.minor))')

rfcxml= \
	rfc6787.xml		\
	rfc7911.xml		\
#	rfc7754.edited.xml	\

rfcxmlfiles = $(addprefix tests/input/, $(rfcxml))
rfctxt      = $(addsuffix .txt, $(basename $(rfcxml)))
rfctest     = $(addsuffix .tests, $(basename $(rfcxml)))
rfctxtfiles = $(addprefix tests/out/, $(rfctxt))
rfctests    = $(addprefix tests/out/, $(rfctest))

draftxml = \
	draft-template.xml		\
	draft-miek-test.xml		\
#

draftxmlfiles = $(addprefix tests/input/, $(draftxml))
drafttxt      = $(addsuffix .txt, $(basename $(draftxml)))
drafttest     = $(addsuffix .tests, $(basename $(draftxml)))
drafttxtfiles = $(addprefix tests/out/, $(drafttxt))
drafttests    = $(addprefix tests/out/, $(drafttest))

pyfiles  = $(wildcard  xml2rfc/*.py) $(wildcard  xml2rfc/writers/*.py)


env/bin/python:
	echo "Install virtualenv in $$PWD/env/ in order to run tests locally."

.PHONY: install
install:
	python --version
	python setup.py --quiet install
	rm -rf xml2rfc.egg-info/

test:	install flaketest xml2rfc/data/v3.rng pytests

flaketest:
	pyflakes xml2rfc
	@[ -d tests/failed/ ] && rm -f tests/failed/*

pytests:
	python test.py --verbose

CHECKOUTPUT=	\
	groff -ms -K$$type -T$$type tmp/$$doc.nroff | ./fix.pl | $$postnrofffix > tmp/$$doc.nroff.txt ;	\
	for type in .raw.txt .txt .nroff .html .exp.xml .v2v3.xml .prepped.xml ; do					\
	  diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' tests/valid/$$doc$$type tmp/$$doc$$type || { echo "Diff failed for tmp/$$doc$$type output (1)"; read -p "Copy [y/n]? " REPLY; if [ "$$REPLY" = "y" ]; then cp -v tmp/$$doc$$type tests/valid/; else exit 1; fi; } \
	done ; if [ $$type = ascii ]; then echo "Diff nroff output with xml2rfc output:";\
	diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' tmp/$$doc.nroff.txt tmp/$$doc.txt || { echo 'Diff failed for .nroff.txt output'; exit 1; }; fi

# ----------------------------------------------------------------------
#
# Generic rules

%.rng: %.rnc
	trang $< $@

%.tests: %.txt.test %.raw.txt.test %.nroff.test %.html.test %.exp.xml.test %.nroff.txt %.v2v3.xml.test %.text.test %.pages.text.test %.v3.$(py).html.test %.prepped.xml.test
	@echo " Diffing .nroff.txt against regular .txt"
	@doc=$(basename $@); diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' $$doc.nroff.txt $$doc.txt || { echo 'Diff failed for $$doc.nroff.txt output'; exit 1; }
	@echo " Checking v3 validity"
	@doc=$(basename $@); printf ' '; xmllint --noout --relaxng xml2rfc/data/v3.rng $$doc.prepped.xml

tests/out/%.txt tests/out/%.raw.txt tests/out/%.nroff tests/out/%.html tests/out/%.txt tests/out/%.exp.xml : tests/input/%.xml install
	@echo "\n Processing $<"
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --base tests/out/ --raw --legacy --text --nroff --html --exp --strict $<"

tests/out/%.v2v3.xml: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --v2v3 --strict --legacy-date-format $< --out $@"
	@doc=$(basename $@); printf ' '; xmllint --noout --xinclude --relaxng xml2rfc/data/v3.rng $$doc.xml
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --v2v3 --strict --legacy-date-format --add-xinclude $< --out $@"

tests/out/%.prepped.xml: tests/input/%.xml tests/out/%.v3.$(py).html tests/out/%.text install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out $@ --prep $<"
	@echo " Checking generation of .html from prepped .xml"
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out $(basename $@).$(py).html --html --external --legacy-date-format $@" 2> /dev/null || { err=$$?; echo "Error output when generating .html from prepped .xml"; exit $$err; }
	@diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' -I '$(generator_regex)' -I 'rel="alternate"' tests/out/$(notdir $(basename $(basename $@))).v3.$(py).html $(basename $@).$(py).html || { echo "Diff failed for $(basename $@).$(py).html output (2)"; exit 1; }
	@echo " Checking generation of .text from prepped .xml"
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out $(basename $@).text --text --no-pagination --external --legacy-date-format $@" 2> /dev/null || { err=$$?; echo "Error output when generating .text from prepped .xml"; exit $$err; }
	@diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' -I '$(generator_regex)' -I 'rel="alternate"' tests/out/$(notdir $(basename $(basename $@))).text $(basename $@).text || { echo "Diff failed for $(basename $@).text output (2)"; exit 1; }

# These contains index sections, which renders with different whitespace from
# prepped source than directly.  Don't compare html from prepped with master
# for these:
tests/out/draft-miek-test.prepped.xml: tests/input/draft-miek-test.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out $@ --prep $<"
tests/out/draft-v3-features.prepped.xml: tests/input/draft-v3-features.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out $@ --prep $<"

tests/out/%.text: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --text --v3 --strict --no-pagination --legacy-date-format $< --out $@"

tests/out/%.pages.text: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --text --v3 --strict --legacy-date-format $< --out $@"

tests/out/%.bom.text: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --text --v3 --strict --bom $< --out $@"

tests/out/%.wip.text: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --text --v3 --strict --id-is-work-in-progress $< --out $@"

tests/out/%.v3.$(py).html: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --html --v3 --external --strict --legacy-date-format --rfc-reference-base-url https://rfc-editor.org/rfc --id-reference-base-url https://tools.ietf.org/html/ $< --out $@"

tests/out/%.pdf: tests/input/%.xml install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --pdf --v3 --legacy-date-format --rfc-reference-base-url https://rfc-editor.org/rfc --id-reference-base-url https://tools.ietf.org/html/ $< --out $@"

.PRECIOUS: tests/out/%.txt tests/out/%.raw.txt tests/out/%.nroff tests/out/%.nroff.txt tests/out/%.html tests/out/%.txt tests/out/%.exp.xml tests/out/%.v2v3.xml tests/out/%.prepped.xml tests/out/%.text tests/out/%.v3.$(py).html %.prepped.xml %.nroff.txt 

%.prepped.xml: %.v2v3.xml
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out $@ --prep $<"

%.v2v3.text: %.v2v3.xml
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --utf8 --out $@ --text --v3 $<"

%.test: %
	@echo " Diffing $< against master"
	@diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(generator_regex)' tests/valid/$(notdir $<) $< || { echo "Diff failed for $< output (2)"; read -p "Copy [y/n]? " REPLY; if [ "$$REPLY" = "y" ]; then cp -v $< tests/valid/; else exit 1; fi; }

%.nroff.txt: %.nroff
	@echo " Creating $@ from $<"
	@if [ "$(findstring /rfc,$<)" = "/rfc" ]; then groff -ms -Kascii -Tascii $< | ./fix.pl > $@; else groff -ms -Kascii -Tascii $< | ./fix.pl | sed 1,2d > $@; fi

%.min.js: %.js
	bin/uglifycall $<

# ----------------------------------------------------------------------

old-drafttest: cleantmp install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 tests/input/draft-template.xml"
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out tmp/draft-template.prepped.xml --prep tmp/draft-template.v2v3.xml "
	doc=draft-template ; postnrofffix="sed 1,2d" ; type=ascii; $(CHECKOUTPUT)

miektest: cleantmp install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 tests/input/draft-miek-test.xml"
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --out tmp/draft-miek-test.prepped.xml --prep tmp/draft-miek-test.v2v3.xml"
	doc=draft-miek-test ; postnrofffix="sed 1,2d" ; type=ascii; $(CHECKOUTPUT)

cachetest: cleantmp install
	@echo "\n Clearing cache ..."
	@PS4=" " /bin/bash -cx "xml2rfc --cache .cache --clear-cache"
	@echo " Filling cache ..."
	@PS4=" " /bin/bash -cx "xml2rfc --cache .cache tests/input/rfc6787.xml --base tmp/ --raw"
	@echo " Running without accessing network ..."
	@PS4=" " /bin/bash -cx "xml2rfc --cache .cache tests/input/rfc6787.xml --no-network --base tmp/ --raw"


rfctest: cleantmp env/bin/python install $(rfctests)

drafttest: cleantmp env/bin/python install $(drafttests) dateshifttest

# rfctest: cleantmp env/bin/python install $(rfctests)
# 	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --utf8tests/input/rfc6787.xml --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 --prep"
# 	doc=rfc6787 ; postnrofffix="cat" ; type=ascii; $(CHECKOUTPUT)
# 	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --utf8tests/input/rfc7754.edited.xml --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 --prep"
# 	doc=rfc7754.edited ; postnrofffix="cat" ; type=ascii; $(CHECKOUTPUT)
# 	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --utf8tests/input/rfc7911.xml --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 --prep"
# 	doc=rfc7911 ; postnrofffix="cat" ; type=ascii; $(CHECKOUTPUT)

unicodetest: cleantmp  env/bin/python install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 --prep tests/input/unicode.xml "
	doc=unicode ; postnrofffix="sed 1,2d" ; type=ascii; $(CHECKOUTPUT)

utf8test: cleantmp  env/bin/python install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --base tmp/ --raw --legacy --text --nroff --html --exp --v2v3 --prep -q tests/input/utf8.xml"
	@doc=utf8 ; postnrofffix="cat" ; type=utf8; $(CHECKOUTPUT)

v3featuretest: tests/out/draft-v3-features.prepped.xml.test tests/out/draft-v3-features.text.test tests/out/draft-v3-features.v3.$(py).html.test

dateshifttest: cleantmp install
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --date 2013-02-01 --out tmp/draft-miek-test.dateshift.txt --text tests/input/draft-miek-test.xml"
	@diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' tests/valid/draft-miek-test.dateshift.txt tmp/draft-miek-test.dateshift.txt || { echo "Diff failed for draft-miek-test.dateshift.txt output"; exit 1; } 

elementstest: tests/out/elements.prepped.xml.test tests/out/elements.text.test tests/out/elements.pages.text.test tests/out/elements.v3.$(py).html.test

bomtest: tests/out/elements.bom.text.test

wiptest: tests/out/elements.wip.text.test

cleantmp:
	@[ -d tmp ] || mkdir -p tmp
	@[ -d tmp ] && rm -f tmp/*
	@[ -d tests/out ] || mkdir -p tests/out
	@[ -d tests/out ] && rm -f tests/out/* && cp xml2rfc/templates/rfc2629* tests/out/


tests: minify test flaketest cachetest drafttest rfctest utf8test v3featuretest elementstest bomtest wiptest

noflakestests: install pytests regressiontests

regressiontests: drafttest rfctest

minify: xml2rfc/data/metadata.min.js



test2:	test
	@PS4=" " /bin/bash -cx "xml2rfc --cache tests/cache --no-network --utf8 tests/input/rfc6635.xml --legacy --text --out tmp/rfc6635.txt	&& diff -u -I '$(datetime_regex)' -I '$(version_regex)' -I '$(date_regex)' tests/valid/rfc6635.txt tmp/rfc6635.txt "

upload: install
	rst2html changelog > /dev/null	# verify that the changelog is valid rst
	python setup.py sdist upload --sign
	python setup.py install
	rsync dist/xml2rfc-$(shell xml2rfc --version).tar.gz /www/tools.ietf.org/tools/xml2rfc2/cli/ || true
	toolpush /www/tools.ietf.org/tools/xml2rfc2/cli/


changes:
	svn log -r HEAD:950 | sed -n -e 's/^/  * /' -e '1,/^  \* Set version info and settings back to development mode/p' | egrep -v -- '^  \* (----------|r[0-9]+ |$$)' | head -n -1 | tac | sed 's/$$/\n/' | fold -s -w 76 | sed -r 's/^([^ ])/    \1/'