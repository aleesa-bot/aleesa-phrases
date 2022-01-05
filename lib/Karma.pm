package Karma;

use 5.018;
use strict;
use warnings;
use utf8;
use open qw (:std :utf8);

use English qw ( -no_match_vars );
use Carp qw (cluck);
use CHI;
use CHI::Driver::BerkeleyDB;
use Log::Any qw ($log);
use Mojo::Util qw (trim);

use Conf qw (LoadConf);

use version; our $VERSION = qw (1.0);
use Exporter qw (import);
our @EXPORT_OK = qw (KarmaSet KarmaGet);

my $c = LoadConf ();
my $cachedir = $c->{cachedir};
my $max = 5;

# swallow phrase and return answer
sub KarmaSet (@) {
	my $chatid = shift;
	my $phrase = shift;
	my $action = shift;

	$phrase = trim ($phrase);

	if ((! defined $phrase) || $phrase eq '') {
		$phrase = ' ';
	}

	my $cache = CHI->new (
		driver => 'BerkeleyDB',
		root_dir => $cachedir,
		namespace => __PACKAGE__ . '_' . $chatid
	);

	my $score = $cache->get ($phrase);

	if (defined $score) {
		if ($action eq '++') {
			$score++;
		} else {
			$score--;
		}
	} else {
		if ($action eq '++') {
			$score = 1;
		} else {
			$score = -1;
		}
	}

	if ($cache->set ($phrase, $score, 'never') != $score) {
		$log->error ('[ERROR] Cache error: unable to set karma.');
	}

	if ($score < -1 && (($score % (0 - $max)) + 1) == 0) {
		if ($phrase eq ' ') {
			return sprintf 'Зарегистрировано пробитие дна, карма пустоты составляет %d', $score;
		} else {
			return sprintf 'Зарегистрировано пробитие дна, карма %s составляет %d', $phrase, $score;
		}
	} else {
		if ($phrase eq ' ') {
			return sprintf 'Карма пустоты составляет %d', $score;
		} else {
			return sprintf 'Карма %s составляет %d', $phrase, $score;
		}
	}
}

# just return answer
sub KarmaGet (@) {
	my $chatid = shift;
	my $phrase = shift;

	$phrase = trim ($phrase);

	if ((! defined $phrase) || $phrase eq '') {
		$phrase = ' ';
	}

	my $cache = CHI->new (
		driver => 'BerkeleyDB',
		root_dir => $cachedir,
		namespace => __PACKAGE__ . '_' . $chatid
	);

	my $score = $cache->get ($phrase);

	unless (defined $score) {
		$score = 0;
	}

	if ($phrase eq ' ') {
		return sprintf 'Карма пустоты составляет %d', $score;
	} else {
		return sprintf 'Карма %s составляет %d', $phrase, $score;
	}
}

1;

# vim: ft=perl noet ai ts=4 sw=4 sts=4:
