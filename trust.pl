use strict;
use warnings;
use Irssi;
use Irssi::Irc;
use Glib;
use POE qw(Loop::Glib Session::Irssi Component::EasyDBI);
use POE::Component::IRC::Common qw( :ALL );

# REGEXES
our $punc_rx = qr([?.!]?);
our $nick_rx = qr([a-z0-9^`{}_|\][a-z0-9^`{}_|\-]*)i;
our $chan_rx = qr(#$nick_rx)i;
our $names_rx = qr/^\=\s+($chan_rx)\s+:(.+)?\s+$/;
our $messages_trust = qr/^(trust|distrust|believe|disbelieve)\s+(.+)$/;
our $messages_in_channel = qr/\s+(?:in\s+($chan_rx))\s*/;
our $messages_trust_channel = qr/(.+?)\s+(?:in\s+($chan_rx))\s*$/;

my $dsn = 'dbi:Pg:dbname=********';
my $dbuser = '********';
my $dbpass = '*******';

POE::Component::EasyDBI->spawn(
  alias       => 'EasyDBI',
  dsn	      => $dsn,
  username    => $dbuser,
  password    => $dbpass,
);

POE::Session::Irssi->create(
   inline_states => { 
			_start      => \&_start, 
			_unload     => \&_unload, 
			_shutdown   => \&_shutdown,
			_check_access => \&_check_access,
   },
   irssi_commands => {
	'trust'   => \&_trust_user,
	'believe' => \&_believe_user,
   },
   irssi_signals => {
	'message join' => \&_message_join,
	'nick mode changed' => \&_mode_change, 
	'message nick' => \&_nick_change,
   },
);

sub _start {
  $poe_kernel->sig( 'unload', '_unload' );
  $poe_kernel->alias_set('Irssi::Script::thang');
  return;
}

sub _trust_user {
  my ($data,$server,$witem) = @{ $_[ARG1 ] };
  return unless $data;
  return unless $server and $server->{connected};
  return unless $witem->{type} eq 'CHANNEL';
  my $channel = $server->channel_find( $witem->{name} );
  return unless $channel->{chanop};
  my $mapping = $server->isupport('CASEMAPPING');
  my @nicks = split /\s+/, $data;
  my $session_id = $_[SESSION]->ID();
  foreach my $user ( @nicks ) {
    my $nick = $channel->nick_find( $user );
    next unless $nick;
    my $query = join '!', u_irc( $nick->{nick}, $mapping ), _fix_userhost( $nick->{host} );
    $poe_kernel->post( 'EasyDBI', 'arrayhash', 
  	  {
	    sql => 'select * from trusts where server = ? and channel = ? and identity like ? and mode = ?',
	    placeholders => [ $server->{tag}, u_irc( $witem->{name}, $mapping ), $query, 'o' ],
	    session => $session_id,
	    event => '_check_access',
	    _server => $server->{tag},
	    _type => 'record_mode',
	    _nick => $nick->{nick}, 
	    _uhost => $nick->{host},
	    _chan => $witem->{name},
	    _mode => 'o',
  	  } );
    $witem->command("mode +o " . $nick->{nick} );
  }
  return;
}

sub _believe_user {
  my ($data,$server,$witem) = @{ $_[ARG1 ] };
  return unless $data;
  return unless $server and $server->{connected};
  return unless $witem->{type} eq 'CHANNEL';
  my $channel = $server->channel_find( $witem->{name} );
  return unless $channel->{chanop};
  my $mapping = $server->isupport('CASEMAPPING');
  my @nicks = split /\s+/, $data;
  my $session_id = $_[SESSION]->ID();
  foreach my $user ( @nicks ) {
    my $nick = $channel->nick_find( $user );
    next unless $nick;
    my $query = join '!', u_irc( $nick->{nick}, $mapping ), _fix_userhost( $nick->{host} );
    $poe_kernel->post( 'EasyDBI', 'arrayhash', 
  	  {
	    sql => 'select * from trusts where server = ? and channel = ? and identity like ? and mode = ?',
	    placeholders => [ $server->{tag}, u_irc( $witem->{name}, $mapping ), $query, 'v' ],
	    session => $session_id,
	    event => '_check_access',
	    _server => $server->{tag},
	    _type => 'record_mode',
	    _nick => $nick->{nick}, 
	    _uhost => $nick->{host},
	    _chan => $witem->{name},
	    _mode => 'v',
  	  } );
    $witem->command("mode +v " . $nick->{nick} );
  }
  return;
}

sub _nick_change {
  my ($server,$newnick,$oldnick,$userhost) = @{ $_[ARG1] };
  my $session_id = $_[SESSION]->ID();
  my $mapping = $server->isupport('CASEMAPPING');
  my $query = join '!', u_irc( $newnick, $mapping ), _fix_userhost( $userhost );
  foreach my $channel ( grep { $_->nick_find( $newnick ) } $server->channels() ) {
    next unless $channel->{chanop};
    $poe_kernel->post( 'EasyDBI', 'arrayhash', 
    {
	sql => 'select * from trusts where server = ? and channel = ? and identity like ?',
	placeholders => [ $server->{tag}, u_irc( $channel->{name}, $mapping ), $query ],
	session => $session_id,
	event => '_check_access',
	_server => $server->{tag},
	_type => 'nick',
	_nick => $newnick,
	_chan => $channel->{name},
    } );
  }
  return;
}

sub _message_join {
  my($server,$channel,$nick,$address) = @{ $_[ARG1] };
  return if $server->{nick} eq $nick;
  my $chanobj = $server->channel_find($channel);
  return unless $chanobj;
  return unless $chanobj->{chanop};
  my $mapping = $server->isupport('CASEMAPPING');
  my $session_id = $_[SESSION]->ID();
  
  my $query = join '!', u_irc( $nick, $mapping ), _fix_userhost( $address );

  $poe_kernel->post( 'EasyDBI', 'arrayhash', 
  {
	sql => 'select * from trusts where server = ? and channel = ? and identity like ?',
	placeholders => [ $server->{tag}, u_irc( $channel, $mapping ), $query ],
	session => $session_id,
	event => '_check_access',
	_server => $server->{tag},
	_type => 'join',
	_nick => $nick,
	_chan => $channel,
  } );
  return;
}

sub _mode_change {
  my ($channel,$nick,$by,$mode,$type) = @{ $_[ARG1] };
  return unless $type eq '+';
  my $who = $channel->nick_find($by);
  return unless $who;
  my $session_id = $_[SESSION]->ID();
  $mode = { qw(@ o % h + v) }->{$mode};
  my $mapping = $channel->{server}->isupport('CASEMAPPING');
  my $query = join '!', u_irc( $who->{nick}, $mapping ), _fix_userhost( $who->{host} );
  $poe_kernel->post( 'EasyDBI', 'arrayhash', 
  {
	sql => 'select * from trusts where server = ? and channel = ? and identity like ?',
	placeholders => [ $channel->{server}->{tag}, u_irc( $channel->{name}, $mapping ), $query ],
	session => $session_id,
	event => '_check_access',
	_type => 'mode',
	_server => $channel->{server}->{tag},
	_nick => $who->{nick}, 
	_uhost => $who->{host},
	_chan => $channel->{name},
	_mode => $mode,
	_args => $nick->{nick},
	_ext  => $nick->{host},
	_me => $channel->{server}->{nick},
  } );
  return;
}

sub _check_access {
  my ($kernel,$self,$data) = @_[KERNEL,OBJECT,ARG0];
  my $session_id = $_[SESSION]->ID();
  my $result = $data->{result};
  my $error = $data->{error};
  return if defined $error;
  my $type = $data->{_type};
  my $tag = $data->{_server};
  return if $tag =~ /^(EFNet)$/i;
  my $server = Irssi::server_find_tag($tag);
  return unless $server;
  my $mynick = $server->{nick};
  my $mapping = $server->isupport('CASEMAPPING');
  SWITCH: {
    if ( $type =~ /^(join|nick)$/ ) {
	my $mode = '';
	foreach my $row ( @{ $result } ) {
	  my $rmode = $row->{mode};
	  next if $rmode eq 'v' and $mode =~ /[oh]/;
	  next if $rmode eq 'h' and $mode =~ /o/;
	  $mode = $rmode;
	}
	last SWITCH unless $mode;
	my $channel = $server->channel_find($data->{_chan});
	last SWITCH unless $channel;
	my $Nick = $channel->nick_find( $data->{_nick} );
	if ( $Nick ) {
		last SWITCH if $mode eq 'v' and $Nick->{voice};
		last SWITCH if $mode eq 'h' and $Nick->{halfop};
		last SWITCH if $mode eq 'o' and $Nick->{op};
	}
	$channel->command("mode +$mode " . $data->{_nick} ) if $channel->{chanop};
	last SWITCH;
    }
    if ( $type eq 'mode' ) {
	my $mode = '';
	foreach my $row ( @{ $result } ) {
	  my $rmode = $row->{mode};
	  next if $rmode eq 'v' and $mode =~ /[oh]/;
	  next if $rmode eq 'h' and $mode =~ /o/;
	  $mode = $rmode;
	}
	if ( !$mode and $data->{_mode} =~ /o/ and u_irc( $data->{_args}, $mapping ) eq u_irc( $mynick, $mapping ) ) {
	  my $who = join '!', u_irc( $data->{_nick}, $mapping ), $data->{_uhost};
	  $kernel->post( 'EasyDBI', 'insert', 
	  {
                sql => 'insert into trusts (server,channel,identity,mode) values (?,?,?,?)',
                placeholders => [ $data->{_server}, u_irc( $data->{_chan}, $mapping ), $who, 'o' ],
                session => $session_id,
                event => '_added_user',
	  } );
	  last SWITCH;
	}
	#if ( $data->{_mode} =~ /o/ and u_irc( $data->{_args}, $mapping ) eq u_irc( $mynick, $mapping ) ) {
	#  my $csync = u_irc $data->{_chan}, $mapping;
	#  if ( $self->{CHAN_SYNCING}->{ $csync } ) { 
	#	$self->{CHAN_SYNCING}->{ $csync } = 2;
	#  } else {
	#  	$kernel->yield( '_spread_ops', $data->{_chan} );
	#  }
	#  last SWITCH;
	#}
	last SWITCH unless $mode;
	# Okay dude is trusted.
	my $query = join '!', u_irc( $data->{_args}, $mapping ), _fix_userhost( $data->{_ext} );
  	$kernel->post( 'EasyDBI', 'arrayhash', 
  	{
	  sql => 'select * from trusts where server = ? and channel = ? and identity like ? and mode = ?',
	  placeholders => [ $data->{_server}, u_irc( $data->{_chan}, $mapping ), $query, $data->{_mode} ],
	  session => $session_id,
	  event => '_check_access',
	  _type => 'record_mode',
	  _server => $data->{_server},
	  _nick => $data->{_args}, 
	  _uhost => $data->{_ext},
	  _chan => $data->{_chan},
	  _mode => $data->{_mode},
  	} );
	last SWITCH;
    }
    if ( $type eq 'record_mode' ) {
	last SWITCH if $data->{rows};
	my $who = join '!', u_irc( $data->{_nick}, $mapping ), $data->{_uhost};
	$kernel->post( 'EasyDBI', 'insert', 
	{
                sql => 'insert into trusts (server,channel,identity,mode) values (?,?,?,?)',
                placeholders => [ $data->{_server}, u_irc( $data->{_chan}, $mapping ), $who, $data->{_mode} ],
                session => $session_id,
                event => '_added_user',
	} );
	last SWITCH;
    }
  }
  return;
}

sub _shutdown {
  $POE::Kernel::poe_kernel->alias_remove($_) for $POE::Kernel::poe_kernel->alias_list();
  $POE::Kernel::poe_kernel->alarm_remove_all();
  $POE::Kernel::poe_kernel->call( 'EasyDBI', 'shutdown', 'NOW' );
  print "UNLOADED: Irssi::Script::thang";
  return;
}

sub _unload {
  my $win = Irssi::active_win();
  my $package = $_[ARG1];
  $POE::Kernel::poe_kernel->call( $package, '_shutdown' );
  $POE::Kernel::poe_kernel->sig_handled();
}

sub _fix_userhost {
  my $userhost = shift || return;
  my ($user,$host) = split /\@/, $userhost;

  SWITCH: {
    if ( $user =~ /^~/ ) {
	$user =~ s/~/\%/;
    }
    if ( $user =~ /\d/ ) {
	$user = '%';
    }
    # IP address
    if ( $host =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ ) {
	last SWITCH;
    }
    my @host = split /\./, $host;
    if ( $host[0] =~ /\d/ ) {
	$host[0] = '%';
	$host = join '.', @host;
	last SWITCH;
    }
  }
  return join '@', $user, $host;
}

sub _nick_channels {
  my ($server,$nick) = @_;
  my @channels;
  foreach my $channel ( $server->channels() ) {
     my $cnick = $channel->nick_find( $nick );
     next unless $cnick;
     push @channels, $channel->{name};
  }
  return unless @channels;
  print join(' ', $server->{tag}, $nick, join(',', @channels) );
}

1;
