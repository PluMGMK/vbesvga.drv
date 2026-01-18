#!/usr/bin/perl
#make-ver-headers.plx
# Generate the git{prod,drv,grb}.h files by interrogating the Git history
use warnings;
use strict;

# Overall version is easy because we're just seeing if the full tree
# has been tagged:
chomp(my $overall_verstring = `git describe --tags`);

# Build the gitprod.h header based on that version string
my $gitprod = build_hdr($overall_verstring, "PRODUCT");

# Individual components are more involved, because the tree might have
# been tagged since each one was last touched...
my $vbesvga_verstring = path_verstring("../VBESVGA");
my $vbegrab_verstring = path_verstring("../VBEGRAB");

open GITPROD, ">", "../VBESVGA/res31/gitprod.h" or die "Unable to write product version header for driver";
print GITPROD $gitprod;
close GITPROD;
open GITDRV, ">", "../VBESVGA/res31/gitdrv.h" or die "Unable to write file version header for driver";
print GITDRV build_hdr($vbesvga_verstring, "FILE");
close GITDRV;

open GITPROD, ">", "../VBEGRAB/gitprod.h" or die "Unable to write product version header for grabber";
print GITPROD $gitprod;
close GITPROD;
open GITGRB, ">", "../VBEGRAB/gitgrb.h" or die "Unable to write file version header for grabber";
print GITGRB build_hdr($vbegrab_verstring, "FILE");
close GITGRB;

# Usage: build_hdr(verstring, "FILE" or "PRODUCT")
# Returns the contents of a header file to be included in an RCV,
# which defines VER_{FILE or PRODUCT}VERSION and VER_{FILE or PRODUCT}VERSION_STR,
# and also FINAL if $verstr is a non-beta tag AND it's the FILEVERSION
sub build_hdr {
	my $verstring = shift;
	my $what = shift;

	# remove the leading 'v' for the resource string
	my $versionstr = $verstring =~ s/^v//r;
	my $hdr = "#define VER_${what}VERSION_STR\t\"$versionstr\"\r\n";

	# now convert the version string to numbers...
	my ($majver, $minver, $rev, $subrev);

	my $isbeta = index($verstring,"beta") >= 0;
	my $ontag = not ($verstring =~ /g[a-z0-9]*$/);
	if($isbeta) {
		($majver,$minver,$rev) = $verstring =~ /^v(\d*)\.(\d*)-beta(\d*)/;
		# step the minor version back by one to indicate a beta release...
		if ($minver == 0) {
			$majver -= 1;
			$minver = 99;
		} else {
			$minver -= 1;
		}
	} else {
		($majver,$minver,$rev) = $verstring =~ /^v(\d*)\.(\d*)\.(\d*)/;
	}
	# check for number of commits since tag
	if ($ontag) {
		$subrev = 0;
	} else {
		($subrev) = $verstring =~ /-(\d*)-g[a-z0-9]*$/;
	}

	# add the numbers to the header
	$hdr = $hdr."#define VER_${what}VERSION\t$majver,$minver,$rev,$subrev\r\n";

	# add FINAL if appropriate
	if ($ontag and (not $isbeta) and ($what eq "FILE")) {
		$hdr = $hdr."#define FINAL\t1\r\n";
	}

	return $hdr;
}

sub path_verstring {
	# Find the latest commit that touched the indicated file/folder
	chomp(my $commit = `git log -1 --pretty=format:"%h" "$_[0]"`);

	# See if any non-beta tags contain this commit, and find the first one
	chomp(my $verstring = `git tag --contains $commit | sed /beta/d | head -n 1`);
	return $verstring unless $verstring eq '';

	# No? Maybe a beta tag?
	chomp($verstring = `git tag --contains $commit | head -n 1`);
	return $verstring unless $verstring eq '';

	# OK then, this hasn't been tagged yet, go with a full desc!
	chomp($verstring = `git describe --tags $commit`);
	return $verstring; # Definitely not empty!

	# TODO: check if files have been added / modified?
}
