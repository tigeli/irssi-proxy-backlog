# this script is still experimental, don't expect it to work as expected :)
# see http://wouter.coekaerts.be/site/irssi/proxy_backlog
#
# Updated by kimmoli 2014
#
use Irssi;
use Irssi::TextUI;
use DateTime;
use DateTime::Format::Strptime;

$VERSION = "0.0.4";
%IRSSI = (
	authors         => "Kimmo Lindholm",
	contact         => "kimmo.lindholm@gmail.com",
	name            => "proxy_backlog",
	url             => "",
	description     => "sends backlog from irssi to clients connecting to irssiproxy",
	license         => "GPL",
	changed         => "2014-08-31"
);

Irssi::settings_add_int($IRSSI{'name'}, 'proxy_backlog_lines', 10);
Irssi::settings_add_bool($IRSSI{'name'}, 'proxy_backlog_debug', 0);

sub sendbacklog {
	my ($server) = @_;
	my (@lines) = ();

	# get these here, no need to reload script
	my $backlogLines = Irssi::settings_get_int('proxy_backlog_lines');
	my $timestampLen = length(Irssi::settings_get_str('timestamp_format'));
	my $debug = Irssi::settings_get_bool('proxy_backlog_debug');

	Irssi::print("Sending backlog to proxy client for " . $server->{'tag'});

	CHANNEL: foreach my $channel ($server->channels) { # go through channels of this server

		@lines = ();

		if ($debug) { Irssi::print("Processing channel ". $channel->{'name'}); }
		if (!$debug) { Irssi::signal_add_first('print text', 'stop_sig'); }

		my $window = $server->window_find_item($channel->{'name'});

		if (!defined($window)) {
			Irssi::print("Could not find window for ". $channel->{'name'});
			next CHANNEL;
		}

		my $totalLines = 0;

		my ($timenow) = DateTime->now();
		$timenow->set_time_zone( 'local' );

		for (my $line = $window->view->get_lines; defined($line); $line = $line->next) {
			$totalLines ++;
			my $thisline = $line->get_text(0);
			if ($thisline =~ /BACKLOG SENDING DONE/) { # this the tag from last backlog sending, clear fifo
				@lines = ();
			} else {
				unshift(@lines, $thisline); # add line to fifo
				if ( scalar(@lines) > $backlogLines ) { # and remove oldest line from fifo, if count exceeded
					pop(@lines);
				}
			}
		}
		my $numOfLines = scalar(@lines);

		if ($numOfLines > 0) {
			#Irssi::signal_emit('server incoming', $server,':proxy NOTICE ' . $channel->{'name'} .' :***Backlog starts***');
			LINE: foreach my $thisline (reverse(@lines)) {
				if ($debug) { Irssi::print("this line=" . $thisline ); }

				my $m = "proxy";

				if ($thisline =~ s/<.([^>]+)>//) {
					$m = $1;
				}

				my $hour = 0;
				my $min = 0;

				if ($thisline =~ /^\d{2}:\d{2}/) {
					$hour = substr $thisline, 0, 2;
					$min = substr $thisline, 3, 2;
				}

				if ($thisline =~ s/Day changed to //) {
					if ($debug) { Irssi::print("Changing date ". $thisline ); }
					my $strp = DateTime::Format::Strptime->new(pattern   => '%d %b %Y', on_error  => 'croak');
					$timenow = $strp->parse_datetime( $thisline ); 
					$numOfLines --;
					next LINE;
				}

				$timenow->set_time_zone( 'local' );
				$timenow->set_second( 0 );
				$timenow->set_hour( $hour );
				$timenow->set_minute( $min );

				#just noticed that iso timestamp could use e.g. +03:00 instead of Z - meh - too lazy to change
				my $timeutc = $timenow;
				$timeutc->set_time_zone( 'UTC' );
				my $year = $timeutc->year();
				my $mday = sprintf("%02d", $timeutc->day());	
				my $mon = sprintf("%02d", $timeutc->month());
				$hour = sprintf("%02d", $timeutc->hour());	
				$min = sprintf("%02d", $timeutc->minute());
				
				my $msgType = " PRIVMSG ";
				if ($m =~ /^proxy$/) {
					$msgType = " NOTICE ";
				}
				
				Irssi::signal_emit('server incoming', $server,'@time='. $year .'-'. $mon .'-'. $mday .'T'.$hour .':'. $min .':00.000Z :' . $m . $msgType . $channel->{'name'} .' :' . substr($thisline, ( $timestampLen+1 ) ));
			}

		}
		if ($numOfLines > 0) {
			Irssi::signal_emit('server incoming', $server,':proxy NOTICE ' . $channel->{'name'} .' :Backlog done. Showing '. $numOfLines .' of '. $totalLines );
		}

		if (!$debug) { Irssi::signal_remove('print text', 'stop_sig'); }

		if ($debug) { Irssi::print("Done processing this channel. ". $numOfLines ." rows of ". $totalLines ." sent"); }

		if ($numOfLines > 0) {
			$server->print($channel->{'name'}, "BACKLOG SENDING DONE", MSGLEVEL_NO_ACT);
		}
	}
	Irssi::print("Done sending backlogs");
}

sub stop_sig {
	Irssi::signal_stop();
}

Irssi::signal_add('message irc own_ctcp', sub {
	my ($server, $cmd, $data, $target) = @_;
	print ("cmd:$cmd data:$data target:$target");
	if ($cmd eq 'IRSSIPROXY' && $data eq 'BACKLOG SEND' && $target eq '-proxy-') {
		sendbacklog($server);
	}
});
