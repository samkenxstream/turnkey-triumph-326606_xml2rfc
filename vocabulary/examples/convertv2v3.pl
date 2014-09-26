#!/usr/bin/perl -w

## Convert xml2rfc v2 to xml2rfc v3.
## In particular, this conversion tool removes all elements that are marked as "deprecated" in
## <a href="http://tools.ietf.org/html/draft-hoffman-xml2rfc-08">draft-hoffman-xml2rfc-08</a>,
## and converts them to their intended replacements.

## Original Author: Tony Hansen
## This code is intended to be a demonstration of how xml2rfc v2 to v3 conversion can be done.
## The code is in the public domain.

## TODO STILL: ????????????????
## inside <!DOCTYPE, cut down newlines between [ ]
## is hangIndent used somewhere?
## for PIs, handle multiple-attribute PIs, as in <?rfc toc='yes' tocindent='3' ...?>

use strict;
use XML::Parser;
use Getopt::Std;

my %optargs;
getopts('EC#', \%optargs) or usage();

sub usage {
    print STDERR "Usage: $0 [-C] [-#] [-E]\n";
    print STDERR "convert xml2rfc v2 to v3\n";
    print STDERR "-C\tomit comments about changes that were made\n";
    print STDERR "-#\tprint the ## comments from this script\n";
    print STDERR "-E\tprint WARNINGS and ERRORS to stderr (in addition to within the document)\n";
    exit 1;
}

if ($optargs{"#"}) {
    # print "FILE='" . __FILE__ . "'\n";
    open F, "<", __FILE__ or die "Cannot open " . __FILE__ . ": $!\n";
    my $printing;
    print "<!-- ================================ conversion rules ================================\n";
    while (<F>) {
	if (/^\s*##/) {
	    $printing = 1;
	    $_ =~ s/^\s*##//;
	    print;
	} else {
	    if ($printing) {
		print "\n";
		$printing = undef;
	    } else {
		# nothing
	    }
	}
    }
    close F;
    print "================================ end of conversion rules ================================ -->\n";
}

# hold the PIs
my $haveEntityDeclarations;
my $haveEntityComments = "";
my $usingXIinclude;
my %systemEntities;
my %publicEntities;
my $omitComments = $optargs{C};
my $additionalRfcAttributes = '';
my @insideList;
my @insideListOriginalStyle;
my @insideListElementCount;
my %vspaceElementCounts;
my $compact;

# the current XML path
my @xmlPath;
my $xmlPath;
my $xmlCharVal;
my $elementCount = 0;
my $lastReferenceElementCount = -1;
my %referenceHasTarget;
my %referenceTarget;
my %replacementStack;
my $cdata;
my $output = '';
my $errorOutput = '';
my $expat;
my $filename = '';
my $pendingArtworkAlt;
my $pendingArtworkSrc;

my @emptyElements = (
    'date',	    'iref',	    'vspace',	    'seriesInfo',
    'format'
    );
my %emptyElements = fillHash(1, @emptyElements);

my @ctextElements = (
    'area',	    'city',	    'code',	    'country',
    'cref',	    'email',	    'eref',	    'facsimile',
    'keyword',	    'organization', 'phone',	    'region',
    'spanx',	    'street',	    'title',	    'ttcol',
    'uri',	    'workgroup',    'xref',
    );
my %ctextElements = fillHash(1, @ctextElements);

# these elements get removed, possibly moving information elsewhere
my @removedElements = (
    'facsimile', # 2.24
    'format', # 2.26
    'vspace', # 2.64
    );
my %removedElements = fillHash(1, @removedElements);

# these elements get replaced with something else
my @replacedElements = (
    'list', # 2.33
    'spanx', # 2.51
    );
my %replacedElements = fillHash(1, @replacedElements);

my $REMOVED = 1;
my $KEPT = 2;
my $LOWERCASED = 3;
my %removedPIs = (
    artworkdelimiter => $REMOVED,	    artworklines => $REMOVED,
    authorship => $REMOVED,		    autobreaks => $REMOVED,
    background => $REMOVED,		    colonspace => $REMOVED,
    comments => $KEPT,			    compact => $REMOVED,
    docmapping => $REMOVED,		    editing => $KEPT,
    emoticonic => $REMOVED,		    footer => $REMOVED,
    header => $REMOVED,			    include => $KEPT,
    inline => $REMOVED,			    iprnotified => $REMOVED,
    linkmailto => $REMOVED,		    linefile => $KEPT,
    needLines => $REMOVED,		    notedraftinprogress => $REMOVED,
    private => $REMOVED,		    refparent => $REMOVED,
    rfcedstyle => $REMOVED,		    rfcprocack => $REMOVED,
    slides => $REMOVED,			    sortrefs => $KEPT,
    strict => $REMOVED,			    subcompact => $REMOVED,
    symrefs => $KEPT,			    "text-list-symbols" => $REMOVED,
    toc => $REMOVED,			    tocappendix => $REMOVED,
    tocdepth => $KEPT,			    tocindent => $REMOVED,
    tocnarrow => $REMOVED,		    tocompact => $REMOVED,
    topblock => $REMOVED,		    typeout => $REMOVED,
    useobject => $REMOVED,		    needlines => $LOWERCASED
    );

main();

sub main {
    my $parser = new XML::Parser(
	NoExpand => 1,
	Handlers => {
	    # http://search.cpan.org/dist/XML-Parser/Parser.pm
	    #    Init (Expat)
	    Init       => \&initHandler,
	    #    Final (Expat)
	    Final      => \&finalHandler,
	    #    Start (Expat, Element [, Attr, Val [,...]])
	    Start      => \&startHandler,
	    #    End (Expat, Element)
	    End        => \&endHandler,
	    #    Char (Expat, String)
	    Char       => \&charHandler,
	    #    Proc (Expat, Target, Data)
	    Proc       => \&procHandler,
	    #    Comment (Expat, Data)
	    Comment    => \&commentHandler,
	    #    CdataStart (Expat)
	    CdataStart => \&cdstartHandler,
	    #    CdataEnd (Expat)
	    CdataEnd   => \&cdendHandler,
	    #    Default (Expat, String)
	    Default => \&pdefaultHandler,
	    #    Unparsed (Expat, Entity, Base, Sysid, Pubid, Notation)
	    #    Notation (Expat, Notation, Base, Sysid, Pubid)
	    #    ExternEnt (Expat, Base, Sysid, Pubid)
	    ExternEnt => \&externentHandler,
	    #    ExternEntFin (Expat)
	    ExternEntFin => \&externentfinHandler,
	    #    Entity (Expat, Name, Val, Sysid, Pubid, Ndata, IsParam)
	    Entity => \&entityHandler,
	    #    Element (Expat, Name, Model)
	    #    Attlist (Expat, Elname, Attname, Type, Default, Fixed)
	    Attlist => \&attlistHandler,
	    #    Doctype (Expat, Name, Sysid, Pubid, Internal)
	    Doctype    => \&doctypeHandler,
	    #    * DoctypeFin (Parser)
	    DoctypeFin => \&doctypefinHandler,
	    #    XMLDecl (Expat, Version, Encoding, Standalone)
	    XMLDecl    => \&xmldeclHandler,
	}
	);

    if( $ARGV[0]) { $filename = $ARGV[0]; $parser->parsefile($filename); }
    else          { $filename = "stdin"; $parser->parse( \*STDIN);      }

    ## For the elements that are supposed to be EMPTY, convert the closing "></foo>" tag to "/>".
    ## For the elements that are only contain text and can potentially be empty,
    ## convert the closing "></foo>" tag to "/>".
    for my $el (@emptyElements) {
	$output =~ s(></$el>)(/>)g;
    }

    ## 1.2.3
    ##   o  Deprecate <format> because it is not useful and has caused
    ##      surprise for authors in the past.  If the goal is to provide a
    ##      single URI for a reference, use the "target" attribute on
    ##      <reference> instead.
    ## ...
    ## move first <format target='..'> to enclosing <reference target='..'>
    for my $elementCount (keys %referenceTarget) {
	my $target = $referenceTarget{$elementCount};
	$output =~ s/ elementCount='$elementCount'/ target='$target'/g;
    }

    # fix up any lists that need vspace
    for my $ec (keys %vspaceElementCounts) {
	$output =~ s(<!-- CONVERT opening list elementCount='$ec' -->)(<t>)g;
	$output =~ s(<!-- CONVERT closing list elementCount='$ec' -->)(</t>)g;
    }
    # clean up other places where vspace was NOT added
    $output =~ s(<!-- CONVERT opening list elementCount='\d+' -->)()g;
    $output =~ s(<!-- CONVERT closing list elementCount='\d+' -->)()g;

    # remove the element counts
    $output =~ s/ elementCount='\d+'//g;

    # add blank line between CONVERT comments
    $output =~ s/--><!-- CONVERT/-->\n<!-- CONVERT/g;

    ## B.1.
    ## When using xi:include,
    ##    add to <rfc>, xmlns:xi="http://www.w3.org/2001/XInclude"
    $output =~ s( END-OF-RFC>)( xmlns:xi="http://www.w3.org/2001/XInclude" END-OF-RFC>) if $usingXIinclude;

    ## 1.2.2.  New Attributes for Existing Elements
    ## o  Add "sortRefs", "symRefs", "tocDepth", and "tocInclude" attributes
    ## to <rfc> to cover processor instructions (PIs) that were in v2
    ## that are still needed in the grammar.
    ## ...
    ## Move various PI values into <rfc>
    if ($additionalRfcAttributes ne '') {
	$output =~ s( END-OF-RFC>)($additionalRfcAttributes END-OF-RFC>);
	$output .= comment("added attributes to <rfc> moved from PIs: $additionalRfcAttributes");
    }
    $output =~ s( END-OF-RFC>)(>);

    # check for non-ascii in the output
    $output =~ /^([[:ascii:]]*)/;
    my $ucount = length($1);
    if ($ucount != length($output)) {
	$output .= "\n";
	$output .= comment("WARNING: wide character found at character $ucount of the output");
	# print "ucount=$ucount\n";
	# print "len(output)=" . length($output) . "\n";
    }
    print $output;
    print STDERR $errorOutput if $optargs{E};
}

# nothing to do
sub initHandler  { }
# nothing to do
sub finalHandler { }

## xml declaration handler
sub xmldeclHandler {
    my ($expat, $version, $encoding, $standalone) = @_;
    saveExpat($expat);
    ## replicate <?xml ...?>
    $output .= '<?xml';
    $output .= " version='$version'" if defined($version);
    $output .= " encoding='$encoding'" if defined($encoding);
    $output .= " standalone='" .( $standalone ?  'yes' : 'no') . "'" if defined($standalone);
    $output .= '?>';
}

sub saveExpat {
    $expat = shift;
}

## start element handler
sub startHandler {
    my ( $expat, $element, @attrvals ) = @_;
    saveExpat($expat);

    my $originalElement = $element;
    push @xmlPath, $element;
    $xmlPath = join('/', @xmlPath);
    $xmlCharVal = '';

    my $comments = '';
    my $suffix = '';

    if ($removedElements{$element}) {
	if ($element eq 'facsimile') {
	    ## 1.2.3. Elements and Attributes Deprecated from v2
	    ## o  Deprecate <facsimile> because it is rarely used and is not
	    ## actually useful; <email> is a much more useful way to get in touch
	    ## with authors.
	    ## 2.24.  <facsimile>
	    ## Deprecated.
	    ## ... just remove
	    $comments .= comment("<$element> deprecated and removed");
	} elsif ($element eq 'format') {
	    $comments .= comment("<$element> deprecated and removed");
	    ## 2.26.  <format>
	    ## If the goal is to provide a single URI for a reference,
	    ## use the "target" attribute on <reference> instead.
	    ## ...
	    ## If it has a target attribute, move first target to enclosing
	    ## <reference>.
	    ## Otherwise, just remove.
	    my %attrvals = @attrvals;
	    if (defined($attrvals{target})) {
		if (defined($referenceHasTarget{$lastReferenceElementCount})) {
		    if ($referenceHasTarget{$lastReferenceElementCount} eq $attrvals{target}) {
			$comments .= comment("duplicate <reference target=...>/<format target=...> removed");
		    } else {
			$comments .= comment("WARNING: <reference>/<format target='$attrvals{target}'> found for <reference> that already has different target='$referenceHasTarget{$lastReferenceElementCount}'. Please verify which is correct for promotion.");
		    }
		} elsif (defined($referenceTarget{$lastReferenceElementCount})) {
		    $comments .= comment("additional <reference>/<format target='$attrvals{target}'> values ignored");
		} else {
		    $referenceTarget{$lastReferenceElementCount} = $attrvals{target};
		    $comments .= comment("moving <$element target=...> to enclosing <reference>");
		}
	    }
	} elsif ($element eq 'vspace') {
	    ## 1.2.3. Elements and Attributes Deprecated from v2
	    ## o  Deprecate <vspace> because the major use for it, creating pseudo-
	    ## paragraph-breaks in lists, is now handled properly.
	    ## 2.64.  <vspace>
	    ## Deprecated.
	    ## ...
	    ## When <vspace/> is found in a list, handle it by adding an extra layer of <t></t>
	    ## Otherwise, just remove it.
	    if ($xmlPath =~ /\/list\/t\/vspace$/) {
		my $p = $insideListElementCount[$#insideListElementCount];
		$comments .= comment("<vspace/> inside list converted to nested <t>");
		$vspaceElementCounts{$p} = 1;
		$output .= "</t><t>";
	    } else {
		$comments .= comment("<$element> deprecated and removed");
	    }
	} else {
	    $comments .= comment("removing deprecated element $element");
	}
	$output .= $comments;
	return;
    }

    if ($replacedElements{$element}) {
	if ($element eq 'list') {
	    ## 2.33.  <list>
	    ## Deprecated.  Instead, use <dl> for list/@style "hanging"; <ul> for
	    ## list/@style "empty" or "symbols"; and <ol> for list/@style "letters",
	    ## "numbers", or "format".
	    ## 2.33.1.  'counter' attribute
	    ## Deprecated.  The functionality of this attribute has been replaced
	    ## with <ol>/@start.
	    ## 2.33.2.  'hangIndent' attribute
	    ## Deprecated.
	    ## 2.33.3.  'style' attribute
	    ## Deprecated.
	    ## ...
	    ## convert <list> to other form, depending on style attribute.
	    ## Push list type for </list>.
	    ## During list, change <t> to <li> OR <dd><dt>
	    my %attrvals = @attrvals;
	    my $newelement = "LISTREPLACEMENT";
	    my $newstyle;
	    if (!defined($attrvals{style})) {
		## ???????????????? style needs to be inherited?
		## ???????????????? inheriting style='format Req %d' is tricky
		$attrvals{empty} = 'true';
		if ($#insideList >= 0) {
		    $attrvals{style} = $insideListOriginalStyle[$#insideListOriginalStyle];
		} else {
		    $attrvals{style} = '';
		}
	    }
	    my $curStyle = $attrvals{style};
	    if ($curStyle eq '') {
		## ???????????????? missing style needs to be inherited?
		$newelement = 'ul';
		$comments .= comment("converting empty style to <ul empty=true>");
	    } elsif ($curStyle eq 'hanging') {
		$newelement = 'dl';
	    } elsif ($curStyle eq 'empty') {
		$newelement = 'ul';
	    } elsif ($curStyle eq 'symbols') {
		$newelement = 'ul';
	    } elsif ($curStyle eq 'letters') {
		$newelement = 'ol';
		$newstyle = 'a';
	    } elsif ($curStyle eq 'numbers') {
		$newelement = 'ol';
		$newstyle = '1';
	    } elsif ($curStyle =~ /^format /) {
		$newelement = 'ol';
		$newstyle = $curStyle;
		$newstyle =~ s/^format //;
	    } else {
		$comments .= comment("WARNING: unknown <list style=$curStyle> value");
		$newelement = 'ul';
	    }
	    if (defined($attrvals{counter})) {
		my $counter = $attrvals{counter};
		delete $attrvals{counter};
		$comments .= comment("converting <list counter=...> to <$newelement group=...>");
		$attrvals{group} = $counter;
	    }
	    delete $attrvals{style};
	    $attrvals{style} = $newstyle if (defined($newstyle));

	    ## Replace PI compact=yes/no with list spacing attributes.
	    ## This is not documented in draft-hoffman-xml2rfc.
	    ## 2.19.2.  <dl> 'spacing' attribute
	    ## 2.36.2.  <ol> 'spacing' attribute
	    ## 2.62.2.  <ul> 'spacing' attribute
	    ## ...
	    ## PI compact=yes => dl/ol/ul spacing=compact
	    ## PI compact=no  => dl/ol/ul spacing=normal
	    if (defined($compact)) {
		$attrvals{spacing} = $compact;
	    }

	    @attrvals = %attrvals;
	    $replacementStack{$xmlPath} = $newelement;
	    $comments .= comment("converting <$element> to <$newelement>");
	    push @insideListOriginalStyle, $curStyle;
	    push @insideList, $newelement;
	    push @insideListElementCount, $elementCount;
	    $element = $newelement;
	    # $comments .= comment("pushed elementCount=$elementCount");
	} elsif ($element eq 'spanx') {
	    ## 1.2.3.  Elements and Attributes Deprecated from v2
	    ## o  Deprecate <spanx>; replace it with <strong>, <b>, <em>, <i>, and <tt>.
	    ## 2.51.  <spanx>
	    ## Deprecated.  Use <b>, <i>, and <tt> instead.
	    ## Content model: only text content.
	    ## 2.51.1.  'style' attribute
	    ## Deprecated.
	    ## 2.51.2.  'xml:space' attribute
	    ## Deprecated.
	    ## Allowed values:
	    ## o  "default"
	    ## o  "preserve" (default)
	    my %attrvals = @attrvals;
	    my $newelement;
	    if ($attrvals{style} eq 'strong') {
		$newelement = 'strong';
	    } elsif ($attrvals{style} eq 'verb') {
		$newelement = 'tt';
	    } else {
		$newelement = 'em';
	    }
	    $replacementStack{$xmlPath} = $newelement;
	    $comments .= comment("converting <$element style='$attrvals{style}'> to <$newelement>");
	    $element = $newelement;
	}
    }

    if ($element eq 'figure') {
	if (defined($pendingArtworkAlt)) {
	    $comments .= comment("WARNING: alt='$pendingArtworkAlt' was removed from a previous <figure>, but no <artwork> was found to place it in");
	}
	if (defined($pendingArtworkSrc)) {
	    $comments .= comment("WARNING: alt='$pendingArtworkAlt' was removed from a previous <figure>, but no <artwork> was found to place it in");
	}
	$pendingArtworkAlt = $pendingArtworkSrc = undef;
    } elsif ($element eq 't') {
	if ($#insideList != -1) {
	    my $newelement;
	    my $insideList = $insideList[$#insideList];
	    if ($insideList eq 'dl') {
		$newelement = "dt";
		$comments .= comment("converting <t> to <dt>+<dd>");
	    } elsif ($insideList ne '') {
		$newelement = 'li';
		$comments .= comment("converting <$element> to <$newelement>");
	    }
	    $element = $newelement;
	    push @insideListElementCount, $elementCount;
	    # $comments .= comment("<t> pushed elementCount=$elementCount");
	    $suffix = "<!-- CONVERT opening list elementCount='$elementCount' -->";
	}
    }
    $output .= "<$element elementCount='$elementCount'";
    $elementCount++;
    if ($element eq 'artwork') {
	if (defined($pendingArtworkAlt)) {
	    my %attrvals = @attrvals;
	    if (defined($attrvals{alt})) {
		if ($pendingArtworkAlt ne $attrvals{alt}) {
		    $comments .= comment("WARNING: cannot move enclosing <figure alt='$pendingArtworkAlt'> to <artwork> because of already existing <artwork alt='$attrvals{alt}'>");
		} else {
		    $comments .= comment("duplicate <figure alt='$pendingArtworkAlt'> removed");
		}
	    } else {
		$comments .= comment("adding attributes moved from enclosing <figure>: <artwork $pendingArtworkAlt>");
		$output .= "alt='$pendingArtworkAlt'";
	    }
	    $pendingArtworkAlt = undef;
	}
	if (defined($pendingArtworkSrc)) {
	    my %attrvals = @attrvals;
	    if (defined($attrvals{src})) {
		if ($pendingArtworkSrc ne $attrvals{src}) {
		    $comments .= comment("WARNING: cannot move enclosing <figure src='$pendingArtworkSrc'> to <artwork> because of already existing <artwork src='$attrvals{src}'>");
		} else {
		    $comments .= comment("duplicate <figure src='$pendingArtworkSrc'> removed");
		}
	    } else {
		$comments .= comment("adding attributes moved from enclosing <figure>: <artwork $pendingArtworkSrc>");
		$output .= "src='$pendingArtworkSrc'";
	    }
	    $pendingArtworkSrc = undef;
	}
    }
    my $titleSaved = "";
    my $hangText = "";
    for (my $i = 0; $i < $#attrvals; $i += 2) {
	my $skip;
	my $name = $attrvals[$i];
	my $val = $attrvals[$i+1];

	if ($element eq 'section') {
	    if ($name eq 'title') {
		## 2.48.5 title
		## ... move section/title to <titleelement>
		$comments .= comment("title= moved to <titleelement>");
		$titleSaved = $val;
		$skip = 1;
	    }
	} elsif ($element eq 'texttable') {
	    if ($name eq 'title') {
		## 2.57.6 title
		## ... move texttable/title to <titleelement>
		$comments .= comment("title= moved to <titleelement>");
		$titleSaved = $val;
		$skip = 1;
	    }
	} elsif ($element eq 'artwork') {
	    if (($name eq 'height') ||
		($name eq 'width') ||
		($name eq 'xml:space')) {
		## 2.5.3 artwork/height= is deprecated
		## 2.5.7 artwork/width= is deprecated
		## 2.5.9 artwork/xml:space= is deprecated
		## ... replace with nothing
		$comments .= comment("<$element $name='$val'> deprecated and removed");
		$skip = 1;
	    }
	} elsif ($element eq 'figure') {
	    if ($name eq 'alt') {
		## 1.2.3.  Elements and Attributes Deprecated from v2
		## o  Deprecate the "alt", "height", "src", and "width" attributes in
		## <figure> because they overlap with the attributes in <artwork>.
		## 2.25.2 figure alt= deprecated
		## Deprecated.
		## ... move to enclosed <artwork>
		$skip = 1;
		$comments .= comment("<$element $name=...> moved to enclosing <artwork>");
		$pendingArtworkAlt = $val;
	    } elsif ($name eq 'src') {
		## 1.2.3.  Elements and Attributes Deprecated from v2
		## o  Deprecate the "alt", "height", "src", and "width" attributes in
		## <figure> because they overlap with the attributes in <artwork>.
		## 2.25.6 figure src= deprecated
		## Deprecated.
		## ... move to enclosed <artwork>
		$skip = 1;
		$comments .= comment("<$element $name=...> moved to enclosing <artwork>");
		$pendingArtworkSrc = $val;
	    } elsif ($name eq 'height') {
		## 1.2.3.  Elements and Attributes Deprecated from v2
		## o  Deprecate the "alt", "height", "src", and "width" attributes in
		## <figure> because they overlap with the attributes in <artwork>.
		## 2.25.5 <figure> height= deprecated
		## Deprecated.
		## 2.5.3. <artwork>  'height' attribute
		## Deprecated.
		## ... replace with nothing
		$skip = 1;
		$comments .= comment("<$element $name=...> deprecated and removed");
	    } elsif ($name eq 'width') {
		## 1.2.3.  Elements and Attributes Deprecated from v2
		## o  Deprecate the "alt", "height", "src", and "width" attributes in
		## <figure> because they overlap with the attributes in <artwork>.
		## 2.25.9 <figure> width= deprecated
		## Deprecated.
		## 2.5.7. <artwork> 'width' attribute
		## Deprecated.
		## ... replace with nothing
		$skip = 1;
		$comments .= comment("<$element $name=...> deprecated and removed");
	    } elsif ($name eq 'title') {
		## 1.2.3.  Elements and Attributes Deprecated from v2
		## o  Deprecate the "title" attribute in <section>, <figure>, and
		## <texttable> in favor of the new <titleelement>.
		## 2.25.8 figure title= deprecated
		## Deprecated.  Use <titleelement> instead.
		## ... move it to <titleelement>
		$titleSaved = $val;
		$skip = 1;
	    }
	} elsif ($element eq 'xref') {
	    if ($name eq 'format') {
		## 2.66.1.  xref/'format' attribute
		if (($val eq 'none') ||
		    ($val eq 'title')) {
		    ## xref/format="none"
		    ## This attribute value is deprecated.
		    ## xref/format="title"
		    ## This attribute value is deprecated.
		    $skip = 1;
		    $comments .= comment("<$element $name='$val'> deprecated and removed");
		}
	    } elsif ($name eq 'pageno') {
		## 2.66.2.  xref/'pageno' attribute
		## Deprecated.
		## Allowed values:
		## o  "true"
		## o  "false" (default)
		## ... remove
		$skip = 1;
		$comments .= comment("<$element $name='$val'> deprecated and removed");
	    }
	} elsif ($element eq 'reference') {
	    $lastReferenceElementCount = $elementCount - 1;
	    if ($name eq 'target') {
		$referenceHasTarget{$lastReferenceElementCount} = $val;
	    }
	} elsif (($element eq 'strong') || ($element eq 'tt') || ($element eq 'em')) {
	    ## ?? spanx
	    ## ... see above
	    ## <spanx style='foo'> => <strong>/<em>/<tt>
	    if ($name eq 'style') {
	    } elsif ($name eq 'xml:space') {
		$comments .= comment("<spanx $name=...> deprecated and removed");
	    } else {
		$comments .= comment("WARNING: invalid extension <spanx $name=...> ignored");
	    }
	    $skip = 1;
	} elsif ($element eq 'dt') {
	    if ($name eq 'hangText') {
		$skip = 1;
		$hangText = $val;
		$comments .= comment("moving <t hangText=...> to <dt>");
	    } elsif ($name eq 'hangIndent') {
		$skip = 1;
		$comments .= comment("<$element $name='$val'> deprecated and removed");
	    } elsif ($name ne 'anchor') {
		$comments .= comment("WARNING: unhandled attribute <$originalElement $name='$val'> removed");
		$skip = 1;
	    }
	} elsif ($element eq 'li') {
	    if ($name ne 'anchor') {
		## When under a <list style=hanging>, <t> is handled above.
		## Other types of <t> elements should not have any attributes other than anchor=
		$comments .= comment("WARNING: unhandled attribute <$originalElement $name='$val'> removed.");
		$skip = 1;
	    }
	}

	if (!$skip) {
	    ## be careful with attributes that include a quote -- convert to &quot;
	    $val =~ s/[']/&apos;/g;
	    $output .= " $name='$val'";
	}
    }
    ## When using xi:include,
    ##    add to <rfc>, xmlns:xi="http://www.w3.org/2001/XInclude"
    if ($element eq 'rfc') {
	$output .= ' END-OF-RFC';
    }
    if ($emptyElements{$element}) {
	$output .= "/>";
    } else {
	$output .= ">";
    }
    $output .= $suffix;
    if ($element eq 'dt') {
	$output .= "$hangText</dt><dd>";
    }
    if ($comments ne '') {
	$output .= $comments;
    }
    if ($titleSaved ne '') {
	$output .= "<titleelement>$titleSaved</titleelement>";
    }
}

## end element handler
sub endHandler {
    my ( $expat, $element ) = @_;
    saveExpat($expat);
    my $comments = '';
    my $skip;
    my $prefix = '';

    if ($removedElements{$element}) {
	## just remove these
	$skip = 1;
	$comments .= comment("</$element> removed") unless $emptyElements{$element};
    }
    if ($replacedElements{$element}) {
	my $newelement = $replacementStack{$xmlPath};
	delete $replacementStack{$xmlPath};
	$comments .= comment("</$element> replaced with </$newelement>");
	if ($element eq 'list') {
	    pop @insideList;
	    pop @insideListOriginalStyle;
	    my $p = pop @insideListElementCount;
	    # $comments .= comment("popped elementCount=$p");
	}
	$element = $newelement;
    }
    if ($element eq 't') {
	if ($#insideList != -1) {
	    my $newelement;
	    my $insideList = $insideList[$#insideList];
	    if ($insideList eq 'dl') {
		$newelement = 'dd';
	    } else {
		$newelement = 'li';
	    }
	    $comments .= comment("</$element> replaced with </$newelement>");
	    $element = $newelement;
	    my $p = pop @insideListElementCount;
	    # $comments .= comment("<t> popped elementCount=$p");
	    $prefix = "<!-- CONVERT closing list elementCount='$p' -->";
	}
    }

    if (!$skip && !$emptyElements{$element}) {
	$output .= $prefix;
	$output .= "</$element>";
    }
    $output .= $comments;

    pop @xmlPath;
    $xmlPath = join('/', @xmlPath);
}

## character text handler
sub charHandler {
    my ( $expat, $string ) = @_;
    saveExpat($expat);
    if ($optargs{v}) {
	$output .= "'$string'";
    } else {
	$output .= escapeXml($string);
    }
}

## processing element handler
sub procHandler {
    my ( $expat, $target, $data ) = @_;
    saveExpat($expat);
    ## 1.2.2.  New Attributes for Existing Elements
    ## o  Add "sortRefs", "symRefs", "tocDepth", and "tocInclude" attributes
    ## to <rfc> to cover processor instructions (PIs) that were in v2
    ## that are still needed in the grammar.
    ## ... replace the above with <rfc> attributes and other things.
    ## Pass these PIs through unchanged:
    ##    editing=yes/no
    ##	 comments=yes/no
    ##	 linefile=...
    ## Convert this PI to xi:include:
    ##    include=
    ## Remove other known V2 PIs.
    ## Remove various known extension V2 PIs.
    ## Warning on all other PIs.
    ##
    ## ???????????????? handle multiple-attribute PIs, as in <?rfc toc='yes' tocindent='3' ...?>

    my $skip;
    my $comments = '';

    if ($target eq 'rfc') {
	if (($data =~ /^\s*symrefs='(yes|no)'\s*$/i) ||
	    ($data =~ /^\s*symrefs="(yes|no)"\s*$/i)) {
	    $data =~ s/^symrefs/symRefs/i;
	    $additionalRfcAttributes .= " $data";
	    $comments .= comment("moving PI $target $data to <rfc> element");
	    $skip = 1;
	} elsif (($data =~ /^\s*sortrefs='(yes|no)'\s*$/i) ||
		 ($data =~ /^\s*sortrefs="(yes|no)"\s*$/i)) {
	    $data =~ s/^sortrefs/sortRefs/i;
	    $additionalRfcAttributes .= " $data";
	    $comments .= comment("moving PI $target $data to <rfc> element");
	    $skip = 1;
	} elsif (($data =~ /^\s*toc='(yes|no)'\s*$/i) ||
		 ($data =~ /^\s*toc="(yes|no)"\s*$/i)) {
	    $data =~ s/^toc/tocInclude/i;
	    $additionalRfcAttributes .= " $data";
	    $skip = 1;
	    $comments .= comment("moving PI $target $data to <rfc> element");
	} elsif (($data =~ /^\s*compact='(yes|no)'\s*$/i) ||
		 ($data =~ /^\s*compact="(yes|no)"\s*$/i)) {
	    $compact = ($1 eq 'yes') ? 'compact' : 'normal';
	    $skip = 1;
	    $comments .= comment("moving PI $target $data to <dl>/<ol>/<ul> elements");
	} elsif (($data =~ /^\s*tocdepth='\d+'\s*/i) ||
		 ($data =~ /^\s*tocdepth="\d+"\s*/i)) {
	    $data =~ s/tocdepth/tocDepth/i;
	    $additionalRfcAttributes .= " $data";
	    $comments .= comment("moving PI $target $data to <rfc> element");
	    $skip = 1;
	} elsif ($data =~ /^\s*symrefs=/i) {
	    $comments .= comment("ERROR: symrefs should have a yes|no value, instead found '$data'");
	    $skip = 1;
	} elsif ($data =~ /^\s*sortrefs=/i) {
	    $comments .= comment("ERROR: sortrefs should have a yes|no value, instead found '$data'");
	    $skip = 1;
	} elsif ($data =~ /^\s*toc=/i) {
	    $comments .= comment("ERROR: toc should have a yes|no value, instead found '$data'");
	    $skip = 1;
	} elsif ($data =~ /^\s*tocdepth=/i) {
	    $comments .= comment("ERROR: tocdepth should have a numeric value, instead found '$data'");
	    $skip = 1;
	} elsif (($data =~ /^\s*editing='(yes|no)'\s*$/) ||
		 ($data =~ /^\s*editing="(yes|no)"\s*$/) ||
		 ($data =~ /^\*comments='(yes|no)'\s*$/) ||
		 ($data =~ /^\s*comments="(yes|no)"\s*$/) ||
		 ($data =~ /^\s*linefile='.*'\s*$/) ||
		 ($data =~ /^\s*linefile=".*"\s*$/)) {
	    ## these are allowed through unchanged
	} elsif (($data =~ /^\s*include='(.*)'\s*$/) ||
		 ($data =~ /^\s*include="(.*)"\s*$/)) {
	    ## convert to xi:include
	    my $path = $1;
	    my ($noutput, $ncomments) = xiInclude($path);
	    $output .= $noutput;
	    $comments .= comment("moving include processing instruction to xi:include");
	    $comments .= $ncomments;
	    $skip = 1;
	} elsif (($data =~ /^(.*)='(.*)'\s*$/) ||
		 ($data =~ /^(.*)="(.*)"\s*$/)) {
	    my $name = $1;
	    my $val = $2;
	    if (defined($removedPIs{$name}) && ($removedPIs{$name} == $REMOVED)) {
		$comments .= comment("processing instruction '<?$target $data?>' deprecated and removed");
		$skip = 1;
	    } elsif (defined($removedPIs{$name}) && ($removedPIs{$name} == $LOWERCASED)) {
		$comments .= comment("misspelled processing instruction '<?$target $data?>' deprecated and removed");
		$skip = 1;
	    } else {
		$comments .= comment("WARNING: unrecognized processing instruction '<?$target $data?>' removed(1)");
		$skip = 1;
	    }
	} elsif ($data =~ /^\s*$/i) {
	    $comments .= comment("empty processing instruction '<?$target $data?>' removed");
	    $skip = 1;
	} else {
	    $comments .= comment("WARNING: unrecognized processing instruction '<?$target $data?>' removed(2)");
	    $skip = 1;
	}
    } elsif ($target eq 'xml-stylesheet') {
	$comments .= comment("non-standard processing instruction '<?$target $data?>' removed(4)");
	$skip = 1;
    } elsif ($target eq 'rfc-ext') {
	$comments .= comment("non-standard processing instruction '<?$target $data?>' removed(5)");
	$skip = 1;
    } else {
	## non-rfc PIs
	# $comments .= comment("WARNING: target='$target'");
	$comments .= comment("WARNING: unrecognized processing instruction '<?$target $data?>' removed(3)");
	$skip = 1;
    }

    $output .= "<?$target $data?>" unless $skip;
    if ($comments ne '') {
	$output .= $comments;
    }
}

## comment handler
sub commentHandler {
    my ( $expat, $data ) = @_;
    ## copy through intact
    saveExpat($expat);
    $output .= "<!--$data-->";
}

## cdata start handler
sub cdstartHandler {
    $output .= "<![CDATA[";
    $cdata++ ;
}

## cdata end handler
sub cdendHandler   {
    $output .= "]]>";
    $cdata--
}

## doctype start handler
sub doctypeHandler {
    my ( $expat, $name, $sysid, $pubid, $internal ) = @_;
    saveExpat($expat);
    $name = "" if !defined($name);
    $output .= "<!DOCTYPE $name";
    $output .= " SYSTEM '$sysid'" if defined($sysid);
    $output .= " PUBLIC '$pubid'" if defined($pubid);
    #    $output .= "\n>>>>>>>>>>>>>>>> defined(i)=" . defined($internal);
    $internal = "" if !defined($internal);
    #    $output .= ",internal=$internal\n";
}

## doctype end handler
sub doctypefinHandler {
    my ( $expat ) = @_;
    saveExpat($expat);
    #    $output .= "\n>>>>>>>>>>>>>>>> doctypefin()\n";
    if ($haveEntityDeclarations) {
	$output .= "]";
    }
    $output .= ">";
    $output .= $haveEntityComments;
    $haveEntityComments = "";
}

## default handler, for anything not handled by other handlers
sub pdefaultHandler {
    my ( $expat, $string ) = @_;
    saveExpat($expat);
    ## non-system entities will show up as &FOO;. Just pass them through.
    # $output .= "\n>>>> Default($string)\n";
    $output .= $string;
}

## external entity start handler
sub externentHandler {
    my ($expat, $base, $sysid, $pubid) = @_;
    saveExpat($expat);
    ## convert external entity &foo; references into xi:includes
    # $output .= ">>>>>>>>>>>>>>>> ExternEnt()\n";
    # $output .= "base='$base'" if defined($base);
    my $comments = "";
    my $name = "UNKNOWN";
    if (defined($sysid)) {
	$name = $systemEntities{$sysid};
    } elsif (defined($pubid)) {
	$name = $publicEntities{$pubid};
    } else {
	$comments .= comment(">>>>>>>>>>>>>>>> unknown external entity found <<<<<<<<<<<<<<<<");
    }
    # $output .= "name='$name'\n";
    # $output .= "sysid='$sysid'\n" if defined($sysid);
    # $output .= "pubid='$pubid'\n" if defined($pubid);
    if (defined($sysid)) {
	my ($noutput, $ncomments) = xiInclude($sysid);
	$output .= $noutput;
	$comments .= $ncomments;
    } elsif (defined($pubid)) {
	my ($noutput, $ncomments) = xiInclude($pubid);
	$output .=  $noutput;
	$comments .= $ncomments;
    } else {
	$output .= '&' . $name . ';';
    }
    $output .= $comments;
    return "";
}

## external entity end handler
sub externentfinHandler {
    my ( $e ) = @_;
    #    $output .= ">>>>>>>>>>>>>>>>externentfin()\n";
}

## entity definition handler
sub entityHandler {
    my ($expat, $name, $val, $sysid, $pubid, $ndata, $isparam) = @_;
    saveExpat($expat);
    ## PUBLIC/SYSTEM entity definitions are saved for later xi:include processing
    ## other entity definitions are rendered as-is
    # $output .= ">>>>>>>>>>>>>>>> entity()\n";
    # $output .= "name=$name\n";
    # $output .= "val=" . (defined($val) ? $val : "NOTDEFINED") . "\n";
    # $output .= "sysid=" . (defined($sysid) ? $sysid : "NOTDEFINED") . "\n";
    # $output .= "pubid=" . (defined($pubid) ? $pubid : "NOTDEFINED") . "\n";
    # $output .= "ndata=" . (defined($ndata) ? $ndata : "NOTDEFINED") . "\n";
    # $output .= "isparam=" . (defined($isparam) ? $isparam : "NOTDEFINED") . "\n";
    if (defined($sysid) || defined($pubid)) {
	if (defined($sysid)) {
	    # $output .= " SYSTEM '$sysid'";
	    $systemEntities{$sysid} = $name;
	}
	if (defined($pubid)) { # ???? pubid should have "public-id" "URI" ?
	    # $output .= " PUBLIC '$pubid'";
	    $publicEntities{$pubid} = $name;
	}
	$haveEntityComments .= comment("ENTITY declaration $name saved for xi:include");
    } else {
	if (!$haveEntityDeclarations) {
	    $haveEntityDeclarations = 1;
	    $output .= "[";
	}
	$output .= "<!ENTITY $name";
	$output .= toEntityValues(" '$val'") if defined($val);
	if (defined($sysid)) {
	    $output .= " SYSTEM '$sysid'";
	    $systemEntities{$sysid} = $name;
	}
	if (defined($pubid)) { # ???? pubid should have "public-id" "URI" ?
	    $output .= " PUBLIC '$pubid'";
	    $publicEntities{$pubid} = $name;
	}
	$output .= " NDATA $ndata" if defined($ndata);
	# isparam ????
	$output .= ">";
	# my $ucount = ($output =~ /^[[:ascii:]]*/);
	# print "ucount=$ucount\n";
	# print $output;exit;
    }
}

# as_entity() and entitify() came from
# http://stackoverflow.com/questions/6056048/perl-how-to-replace-extended-characters-by-their-corresponding-entity-in-an-xml
sub as_entity {
    my $char = shift;
    return sprintf("&#x%.4x;", ord($char));
}

sub entitify {
    my $str = shift;
    $str =~ s/([\x80-\x{ffffffff}])/as_entity($1)/ge;
    return $str;
}

# based on code from
# http://c2.com/cgi/wiki?HexDumpInManyProgrammingLanguages
sub hexdump {
    my $str = shift;
    my $start = shift;
    $start = 0 if !defined($start);
    my $end = shift;
    $end = length($str) if !defined($end);
    my $width = 32;
    my $block;
    my $ret = '';
    for (my $left = $end - $start; $left > 0 && substr($str, $start, min($width, $left)); $left -= length($block), $start += length($block)) {
	my $hex = join(" ", (map { sprintf("%02X", ord($_)) } split(//, $block)));
	$hex .= '' x ($width - length($block));
	my $plain = join("", (map { printable($_) ? $_ : "." } split(//, $block)));
	$ret .= "$hex: $plain\n";
    }
    return $ret;
}
sub printable { my $o = ord($_[0]); return $o >= 33 && $o <= 126; }
sub min {
    my $ret = shift;
    for my $n (@_) {
	$ret = $n if ($n < $ret);
    }
    return $ret;
}



sub toEntityValues {
    my $ret = '';
    for my $str (@_) {
	# $ret .= $expat->xml_escape($str);
	$ret .= entitify($str)
    }
    # print STDERR hexdump($ret);
    return $ret;
}

sub attlistHandler {
    my ($expat, $elname, $attname, $type, $default, $fixed) = @_;
    saveExpat($expat);
    $output .= ">>>>>>>>>>>>>>>> attlist()\n";
    $output .= "elname=$elname\n";
    $output .= "attname=$attname\n";
    $output .= "type=$type\n";
    $output .= "default=$default\n";
    $output .= "fixed=$fixed\n";
}

################

sub escapeXml {
    my $str = shift;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    return $str;
}

sub fillHash {
    my $val = shift;
    my %ret;
    for my $name (@_) {
	$ret{$name} = $val;
    }
    return %ret;
}

## comment handler
sub comment {
    my $str = shift;
    $str =~ s/--/- -/g;
    my $line = -1;
    my $col = -1;
    my $loc = "";
    if (defined($expat)) {
	$line = $expat->current_line;
	$col = $expat->current_column;
	$loc = "$filename:$line:$col";
    }
    $errorOutput .= "$loc: $str\n" if ($str =~ /^(WARNING|ERROR):/);
    return "" if $omitComments && ($str !~ /^(WARNING|ERROR):/);
    return "<!-- CONVERT $str -->";
}

## Generate an xi:include tag for ENTITY expansions and PI include=.
## Take care of these relative paths:
## <!ENTITY FOO3552 SYSTEM "reference.FOO.3552.xml">
## <!ENTITY RFC3552 SYSTEM "public/rfc/bibxml/reference.RFC.3552.xml">
## <!ENTITY RFC3552 SYSTEM "http://xml.resource.org/public/rfc/bibxml/reference.RFC.3552.xml">
##
## For relative path processing, differentiate between reference.RFC, reference.I-D, etc. for bibxml, bibxml2, etc.
##    bibxml/reference.RFC.0001.xml
##    bibxml2/reference.ANSI.T1-102.1987.xml
##    bibxml3/reference.I-D.aartsetuijn-nipst.xml
##    bibxml4/reference.W3C.charset-harmful.xml
##    bibxml5/reference.3GPP.01.31.xml
##
## Also, append '.xml' if it's a bibxml reference and it's not present.
sub xiInclude {
    my $path = shift;
    my $comments = "";
    if ($path !~ /\//) {
	if ($path =~ /reference\.RFC\./) {
	    $path = "http://xml.resource.org/public/rfc/bibxml/$path";
	    $comments .= comment("converting relative path to bibxml path");
	} elsif ($path =~ /reference\.I-D\./) {
	    $path = "http://xml.resource.org/public/rfc/bibxml3/$path";
	    $comments .= comment("converting relative path to bibxml3 path");
	} elsif ($path =~ /reference\.W3C\./) {
	    $path = "http://xml.resource.org/public/rfc/bibxml4/$path";
	    $comments .= comment("converting relative path to bibxml4 path");
	} elsif ($path =~ /reference\.3GPP\./) {
	    $path = "http://xml.resource.org/public/rfc/bibxml5/$path";
	    $comments .= comment("converting relative path to bibxml5 path");
	} else {
	    $path = "http://xml.resource.org/public/rfc/bibxml2/$path";
	    $comments .= comment("converting relative path to bibxml2 path");
	}
    } elsif ($path =~ /^public\//) {
	$path = "http://xml.resource.org/$path";
	$comments .= comment("converting relative path to use xml.resource.org");
    } else {
	# no change
    }
    if (($path =~ /\/bibxml/) && ($path !~ /\.xml$/)) {
	$path .= ".xml";
	$comments .= comment("adding .xml to bibxml path");
    }
    $usingXIinclude = 1;
    return ("<xi:include href='$path'/>", $comments);
}