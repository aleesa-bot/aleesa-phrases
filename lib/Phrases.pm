package Phrases;

# Общие модули - синтаксис, кодировки итд
use 5.018;
use strict;
use warnings;
use utf8;
use open qw (:std :utf8);

# Модули для работы приложения
use Log::Any qw ($log);
# Чтобы "уж точно" использовать hiredis-биндинги, загрузим этот модуль перед Mojo::Redis
use Protocol::Redis::XS;
use Mojo::Redis;
use Mojo::IOLoop;
use Mojo::IOLoop::Signal;
use Data::Dumper;

use Conf qw (LoadConf);
use Fortune qw (Fortune);
use Friday qw (Friday);
use Proverb qw (Proverb);

use version; our $VERSION = qw (1.0);
use Exporter qw (import);
our @EXPORT_OK = qw (RunPhrases);

my $c = LoadConf ();
my $fwd_cnt = $c->{'forward_max'} // 5;

# Основной парсер
my $parse_message = sub {
	my $self = shift;
	my $m = shift;
	my $answer = $m;
	$answer->{from} = 'phrases';
	my $send_to = $m->{plugin};
	my $reply;

	if (defined $answer->{misc}) {
		unless (defined $answer->{misc}->{fwd_cnt}) {
			$answer->{misc}->{fwd_cnt} = 1;
		} else {
			if ($answer->{misc}->{fwd_cnt} > $fwd_cnt) {
				$log->error ('Forward loop detected, discarding message.');
				$log->debug (Dumper $m);
				return;
			} else {
				$answer->{misc}->{fwd_cnt}++;
			}
		}

		unless (defined $answer->{misc}->{answer}) {
			$answer->{misc}->{answer} = 1;
		}

		unless (defined $answer->{misc}->{csign}) {
			$answer->{misc}->{csign} = '!';
		}
	} else {
		$answer->{misc}->{answer} = 1;
		$answer->{misc}->{csign} = '!';
		$answer->{misc}->{msg_format} = 0;
	}

	$log->debug ('[DEBUG] Incoming message ' . Dumper ($m));

	if (substr ($m->{message}, 0, 1) eq $answer->{misc}->{csign}) {
		if (substr ($m->{message}, 1) eq 'friday'  ||  substr ($m->{message}, 1) eq 'пятница') {
			$reply = Friday ();
		} elsif (substr ($m->{message}, 1) eq 'proverb'  ||  substr ($m->{message}, 1) eq 'пословица') {
			$reply = Proverb ();
		} elsif (substr ($m->{message}, 1) eq 'fortune'  ||  substr ($m->{message}, 1) eq 'фортунка'  ||
		         substr ($m->{message}, 1) eq 'f'  ||  substr ($m->{message}, 1) eq 'ф') {
			if ($m->{plugin} eq 'telegram') {
				if ($m->{misc}->{good_morning}){
					# fortune mod
					my @intro = (
						'Сегодняшний день пройдёт под эгидой фразы:',
						'Крылатая фраза на сегодня:',
						'Сегодняшняя фраза дня:',
					);

					$reply = sprintf "%s\n```\n%s\n```\n", $intro[irand ($#intro + 1)], trim (Fortune ());
				} else {
					$reply = sprintf "```\n%s\n```\n", trim (Fortune ());
				}
			} else {
				$reply = trim (Fortune ());
			}
		}
	}

	$log->debug ("[DEBUG] Sending message to channel $send_to " . Dumper ($answer));

	if (defined $reply && $answer->{misc}->{answer}) {
		$answer->{message} = $reply;

		$self->json ($send_to)->notify (
			$send_to => $answer
		);
	}

	return;
};

my $__signal_handler = sub {
	my ($self, $name) = @_;
	$log->info ("[INFO] Caught a signal $name");

	if (defined $main::pidfile && -f $main::pidfile) {
		unlink $main::pidfile;
	}

	exit 0;
};


# main loop, он же event loop
sub RunPhrases {
	$log->info ("[INFO] Connecting to $c->{server}, $c->{port}");

	my $redis = Mojo::Redis->new (
		sprintf 'redis://%s:%s/1', $c->{server}, $c->{port}
	);

	$log->info ('[INFO] Registering connection-event callback');

	$redis->on (
		connection => sub {
			my ($r, $connection) = @_;

			$log->info ('[INFO] Triggering callback on new client connection');

			# Залоггируем ошибку, если соединение внезапно порвалось.
			$connection->on (
				error => sub {
					my ($conn, $error) = @_;
					$log->error ("[ERROR] Redis connection error: $error");
					return;
				}
			);

			return;
		}
	);

	my $pubsub = $redis->pubsub;
	my $sub;
	$log->info ('[INFO] Subscribing to redis channels');

	foreach my $channel (@{$c->{channels}}) {
		$log->debug ("[DEBUG] Subscribing to $channel");

		$sub->{$channel} = $pubsub->json ($channel)->listen (
			$channel => sub { $parse_message->(@_); }
		);
	}

	Mojo::IOLoop::Signal->on (
		TERM => $__signal_handler,
		INT  => $__signal_handler
	);

	do { Mojo::IOLoop->start } until Mojo::IOLoop->is_running;
	return;
}

1;

# vim: set ft=perl noet ai ts=4 sw=4 sts=4:
