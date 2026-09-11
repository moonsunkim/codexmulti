#!/usr/bin/perl

use strict;
use warnings;

@ARGV == 2 or die "Usage: scripts/make-icns.pl <AppIcon.iconset> <AppIcon.icns>\n";
my ($iconset, $output) = @ARGV;
my @entries = (
    ["ic04", "icon_16x16.png"],
    ["ic11", "icon_16x16\@2x.png"],
    ["ic05", "icon_32x32.png"],
    ["ic12", "icon_32x32\@2x.png"],
    ["ic07", "icon_128x128.png"],
    ["ic13", "icon_128x128\@2x.png"],
    ["ic08", "icon_256x256.png"],
    ["ic14", "icon_256x256\@2x.png"],
    ["ic09", "icon_512x512.png"],
    ["ic10", "icon_512x512\@2x.png"],
);

my @chunks;
for my $entry (@entries) {
    my ($type, $name) = @$entry;
    my $path = "$iconset/$name";
    open(my $image, "<:raw", $path) or die "cannot read $path: $!\n";
    local $/;
    my $bytes = <$image>;
    close($image) or die "cannot close $path: $!\n";
    substr($bytes, 0, 8) eq "\x89PNG\x0d\x0a\x1a\x0a" or die "$path is not a PNG\n";
    push(@chunks, $type . pack("N", length($bytes) + 8) . $bytes);
}
my $toc_payload = join("", map { substr($_, 0, 8) } @chunks);
my $body = "TOC " . pack("N", length($toc_payload) + 8) . $toc_payload . join("", @chunks);

open(my $icns, ">:raw", $output) or die "cannot write $output: $!\n";
print {$icns} "icns", pack("N", length($body) + 8), $body;
close($icns) or die "cannot close $output: $!\n";
