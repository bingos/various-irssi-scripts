  use Irssi;
  use Irssi::Irc;
  use Glib;
  use POE qw(Loop::Glib Session::Irssi);
  use POE::Component::IRC::Plugin::Connector;
  use POE::Component::IRC::Plugin::NickReclaim;
  use POE::Component::IRC::Plugin::BotAddressed;
  use POE::Component::IRC::Plugin::RSS::Headlines;
  use POE::Component::IRC::Plugin::CTCP;
  use Dev::Bollocks;
  use Text::ParseWords;
  use Acme::POE::Acronym::Generator;

  my %rss_links = ( 'jerk it' => 'http://eekeek.org/jerkcity.cgi',
		    'clock'   => 'http://newbabe.pobox.com/~rspier/cgi-bin/clock.cgi', 
  );

  my $nickname = 'Flibble' . $$;
  my $ircname = 'Flibble the Sailor Bot';
  my $ircserver = 'eu.freenode.net';
  my $port = 6667;

  my $poegen = Acme::POE::Acronym::Generator->new();

  my $ircmod = 'POE::Component::IRC';

  eval "require $ircmod;";

  # We create a new PoCo-IRC object and component.
  my $irc = $ircmod->spawn( 
        nick => $nickname,
        server => $ircserver,
        port => $port,
        ircname => $ircname,
  ) or die "Oh noooo! $!";

  POE::Session::Irssi->create(
	package_states => [
	  'Irssi::Script::flibblebot' => [ qw(_start irc_001 irc_rssheadlines_items irc_bot_addressed) ],
	],
	irssi_commands => {
		killflibble => sub { 
			$_[HEAP]->{irc}->yield( 'shutdown', 'ARGH! THE PAIN!' );
			return;
		},
		flibble => sub {
		   my $heap = $_[HEAP];
		   my ($data,$server,$winit) = @{ $_[ARG1] };
		   my @args = quotewords( '\s+', 0, $data);
		   $heap->{irc}->yield( @args );
		   return;
		},
	},
        heap => { irc => $irc,
		  rss_links => \%rss_links,
		  channels => [ '#perl', '#buubot', '#GumbyBRAIN' ], },
  );

  sub _start {
    my ($kernel,$heap) = @_[KERNEL,HEAP];

    $heap->{_fucktards} = { };
    # We get the session ID of the component from the object
    # and register and connect to the specified server.
    my $irc_session = $heap->{irc}->session_id();
    $kernel->post( $irc_session => register => 'all' );
    $heap->{irc}->plugin_add( 'Connector', POE::Component::IRC::Plugin::Connector->new() );
    $heap->{irc}->plugin_add( 'CTCP', POE::Component::IRC::Plugin::CTCP->new() );
    $heap->{irc}->plugin_add( 'NickReclaim', POE::Component::IRC::Plugin::NickReclaim->new() );
    $heap->{irc}->plugin_add( 'BotAddressed', POE::Component::IRC::Plugin::BotAddressed->new() );
    $heap->{irc}->plugin_add( 'GetHeadlines', POE::Component::IRC::Plugin::RSS::Headlines->new() );
    $kernel->post( $irc_session => connect => { } );
    undef;
  }

  sub irc_001 {
    my ($kernel,$sender,$heap) = @_[KERNEL,SENDER,HEAP];

    # Get the component's object at any time by accessing the heap of
    # the SENDER
    my $poco_object = $sender->get_heap();
    # In any irc_* events SENDER will be the PoCo-IRC session
    $kernel->post( $sender => join => $_ ) for @{ $heap->{channels} };
    undef;
  }

  sub irc_bot_addressed {
    my ($kernel,$heap,$sender,$who,$where,$what) = @_[KERNEL,HEAP,SENDER,ARG0,ARG1,ARG2];
    my ($nick,$userhost) = split /!/, $who;
    my $channel = $where->[0];
    my $irc = $sender->ID();
    my $key = "$irc,$channel,$userhost";
    my $last = delete $heap->{_fucktards}->{ $key };
    $heap->{_fucktards}->{ $key } = time();
    return if $last and ( time() - $last < 60 );
    my ($command) = $what =~ /^\s*([a-zA-Z_0-9 ]+)[?.!]?\s*$/;
    if ( uc( $command ) eq 'BOLLOCKS' ) {
	$kernel->post( $sender, 'privmsg', $channel, "$nick: " . ucfirst( Dev::Bollocks->rand(10) ) );
	return;
    }
    if ( uc( $command ) eq 'POEIT' ) {
	$kernel->post( $sender, 'privmsg', $channel, "$nick: " . scalar $poegen->generate() );
	return;
    }
    my $url = $heap->{rss_links}->{lc $command};
    $kernel->yield( 'get_headline', { url => $url, _nick => $nick, _chan => $channel } ) if $url;
    undef;
  }

  sub irc_rssheadlines_items {
    my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
    my $nick = delete $args->{_nick};
    my $chan = delete $args->{_chan};
    $kernel->post( $sender, 'privmsg', $chan, join(' ', "$nick:", @_[ARG1..$#_] ) );
    undef;
  }

  sub UNLOAD {
    $poe_kernel->signal( $poe_kernel, 'POCOIRC_SHUTDOWN', 'ARGH! THE PAIN!' );
  }
