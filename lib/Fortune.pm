package Fortune;
# Прокатят любые источники из fortune_mod. Текстовой файл с разделителем "\n%\n" мнжду фразами.

use 5.018; ## no critic (ProhibitImplicitImport)
use strict;
use warnings;
use utf8;
use open qw (:std :utf8);
use Encode qw (decode);
use English qw ( -no_match_vars );
use Carp qw (croak);
use File::Path qw (make_path);
use Log::Any qw ($log);
use Math::Random::Secure qw (irand);
use SQLite_File ();

use Conf qw (LoadConf);

use version; our $VERSION = qw (1.0);
use Exporter qw (import);
our @EXPORT_OK = qw (Seed Fortune);

my $c = LoadConf ();
my $dir = $c->{fortune}->{dir};
my $srcdir = $c->{fortune}->{srcdir};

sub Seed () {
	unless (-d $dir) {
		make_path ($dir)  ||  croak "Unable to create $dir: $OS_ERROR";
	}

	my $backingfile = sprintf '%s/fortune.sqlite', $dir;

	if (-e $backingfile) {
		unlink $backingfile   ||  croak "Unable to remove $backingfile: $OS_ERROR";
	}

	tie my @fortune, 'SQLite_File', $backingfile  ||  croak "Unable to tie to $backingfile: $OS_ERROR";

	opendir (my $srcdirhandle, $srcdir)  ||  croak "Unable to open $srcdir: $OS_ERROR";

	while (my $fortunefile = readdir $srcdirhandle) {
		my $srcfile = sprintf '%s/%s', $srcdir, $fortunefile;

		unless (-e $srcfile) {
			next;
		}

		if ($fortunefile =~ m/^\.+$/) { ## no critic (RegularExpressions::RequireDotMatchAnything)
			next;
		}

		open (my $fh, '<', $srcfile)  ||  croak "Unable to open $srcfile, $OS_ERROR";
		# set correct phrase delimiter
		local $INPUT_RECORD_SEPARATOR = "\n%\n";

		while (readline $fh) {
			my $phrase = substr $_, 0, -3;
			push @fortune, $phrase;
		}

		close $fh;  ## no critic (InputOutput::RequireCheckedSyscalls, InputOutput::RequireCheckedOpen)
	}

	closedir $srcdirhandle;
	untie @fortune;
	return;
}

# Просто вернём ответ
sub Fortune () {
	my $backingfile = sprintf '%s/fortune.sqlite', $dir;

	tie my @array, 'SQLite_File', $backingfile  ||  do {
		$log->error ("[ERROR] Unable to tie to $backingfile: $OS_ERROR");
		return '';
	};

	my $phrase = $array[irand ($#array + 1)];
	# decode?
	$phrase = decode 'UTF-8', $phrase;
	untie @array;
	return $phrase;
}

1;

# vim: ft=perl noet ai ts=4 sw=4 sts=4:
