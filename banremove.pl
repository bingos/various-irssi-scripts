use Irssi;
use Irssi::Irc;
use Glib;

use POE qw(Loop::Glib);
use POE::Session::Irssi;

$VERSION = "0.2";
%IRSSI = (
    authors     => 'Kidney BinGOs',
    contact     => 'chris[at]bingosnet.co.uk',
    name        => 'banremove',
    description => 'ban and remove lamers at the flick of a switch',
    license     => 'GPL',
    url         => 'http://gumbynet.org/',
);


my $session = POE::Session::Irssi->create (
  package_states => [
    'Irssi::Script::banremove' => [qw(_start banremove stfu getshot silence event_mode)],
  ],
  heap => { SERVER_TAG => 'Freenode' },
);

sub _start {
  my ($kernel,$heap,$session) = @_[KERNEL,HEAP,SESSION];
  delete $heap->{ban};
  delete $heap->{stfu};
  Irssi::signal_add( 'event mode', $session->postback( 'event_mode', $heap->{SERVER_TAG}, '#perl' ) );
  Irssi::command_bind( 'rban' => $session->postback( 'banremove', $heap->{SERVER_TAG}, '#perl' ) );
  Irssi::command_bind( 'stfu' => $session->postback( 'stfu', $heap->{SERVER_TAG}, '#perl' ) );
  undef;
}

sub banremove {
  my ($kernel,$heap,$session) = @_[KERNEL,HEAP,SESSION];
  my ($net,$channel) = @{ $_[ARG0] };
  my ($line,$server,$winit) = @{ $_[ARG1] };
  my $awin = Irssi::active_win();
  return unless $line;
  return unless $winit;
  return unless $net eq $server->{tag} and $winit->{type} eq 'CHANNEL' and $winit->{name} eq $channel;
  my $chan = $winit;
  my ($args,@args) = split /\s+/, $line;
  my $reason = join ' ', @args;
  my $n = $chan->nick_find($args);
  unless ( $n ) {
	Irssi::print("No such nick $args");
	return;
  }
  my $nick = $n->{nick};
  my $host = ( split /\@/, $n->{host} )[1];
  if ( $chan->{chanop} ) {
    $kernel->yield( getshot => $chan => $nick => $host => $reason );
  } else {
    $heap->{ban} = [ $nick, $host, $reason ];
    $server->command("MSG ChanServ op $channel");
  }
  undef;
}

sub stfu {
  my ($kernel,$heap,$session) = @_[KERNEL,HEAP,SESSION];
  my ($net,$channel) = @{ $_[ARG0] };
  my ($args,$server,$winit) = @{ $_[ARG1] };
  return unless $args;
  return unless $winit;
  return unless $net eq $server->{tag} and $winit->{type} eq 'CHANNEL' and $winit->{name} eq $channel;
  my $chan = $winit;
  $args = ( split /\s+/, $args )[0];
  my $n = $chan->nick_find($args);
  unless ( $n ) {
	Irssi::print("No such nick $args");
	return;
  }
  my $nick = $n->{nick};
  my $host = ( split /\@/, $n->{host} )[1];
  if ( $chan->{chanop} ) {
    $kernel->yield( silence => $chan => $nick => $host );
  } else {
    $heap->{stfu} = [ $nick, $host ];
    $server->command("MSG ChanServ op $channel");
  }
  undef;
}

sub getshot {
  my ($kernel,$heap,$session,$chan,$nick,$host,$reason) = @_[KERNEL,HEAP,SESSION,ARG0,ARG1,ARG2,ARG3];
  my $channel = $chan->{name};
  $reason = 'Bye bye' unless $reason;
  $chan->command("MODE $channel +b *!*\@$host");
  $chan->command("QUOTE REMOVE $channel $nick :$reason");
  $chan->command("MODE $channel -o " . $chan->{ownnick}->{nick});
  undef;
}

sub silence {
  my ($kernel,$heap,$session,$chan,$nick,$host) = @_[KERNEL,HEAP,SESSION,ARG0,ARG1,ARG2];
  my $channel = $chan->{name};
  $chan->command("MODE $channel +q *!*\@$host");
  $chan->command("MODE $channel -o " . $chan->{ownnick}->{nick});
  undef;
}

sub event_mode {
  my ($kernel,$heap,$session) = @_[KERNEL,HEAP,SESSION];
  my ($net,$channel) = @{ $_[ARG0] };
  my ($server,$args,$mnick,$addr) = @{ $_[ARG1] };
  my ($target,$modes,$modeparms) = split(" ",$args,3);
  return unless uc( $target ) eq uc( $channel );
  my $chan = $server->channel_find($channel);
  return unless $chan;
  return unless $chan->{chanop};
  my $ban = delete $heap->{ban};
  my $stfu = delete $heap->{stfu};
  $kernel->yield( getshot => $chan => @{ $ban } ) if $ban;
  $kernel->yield( silence => $chan => @{ $stfu } ) if $stfu;
  undef;
}

1;
