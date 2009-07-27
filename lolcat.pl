use strict;
use Irssi;
use Acme::LOLCAT ();

my $VERSION = '2.77';
my %IRSSI = (
  authors	=> 'Chris Williams',
);

sub cmd_lolcat {
  my ($data,$server,$witem) = @_;
  if (!$server || !$server->{connected}) {
    Irssi::print("Not connected to server");
    return;
  }
  return unless $data;
  return unless $witem;
  my $output = Acme::LOLCAT::translate( $data );
  $witem->command("/ $output");
  return 1;
}

Irssi::command_bind('lolcat', 'cmd_lolcat');
