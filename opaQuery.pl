#!/usr/bin/perl
# -----------------------------------------
# Program : opaQuery.pl (OpenStreetMap Overpass-API Query Utility)
# Version : 0.1  - 2012-06-05
#           0.2  - 2012-07-14 help text enlarged
#           0.3  - 2012-07-29 help text enlarged
#           0.3a - 2012-09-07 help text enlarged
#           0.4  - 2012-10-06 -prefix option, help text enlarged
#
# Copyright (C) 2012 Klaus Tockloth
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Contact (eMail): <freizeitkarte@googlemail.com>
#
# Further information:
# - http://wiki.openstreetmap.org/wiki/Overpass_API/Language_Guide
# - http://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL
#
# Test:
# perl opaQuery.pl 'node ["name"="Gielgen"] (50.7, 7.1, 50.8, 7.2); out meta;'
# perl opaQuery.pl 'node ["highway"="bus_stop"] ["shelter"="yes"] (50.7, 7.1, 50.8, 7.2); out meta;'
# -----------------------------------------

use warnings;
use strict;

# General
use English;
use File::Basename;

use LWP::UserAgent;
use URI::QueryParam;
use Encode;
use Getopt::Long;

my $EMPTY        = q{};
my $osm_response = $EMPTY;
my $osm_xmlref   = $EMPTY;

my $osm_service_root = 'http://overpass-api.de/api/interpreter';

my $ua = $EMPTY;
my $rc = 0;

# configuration defaults (overwritten by read_Program_Configuration())
my $http_timeout      = 190;
my $http_proxy        = $EMPTY;
my $display_response  = 1;
my $terminal_encoding = 'utf8';
my $file_encoding     = 'utf8';

my ( $appbasename, $appdirectory, $appsuffix ) = fileparse ( $0, qr/\.[^.]*/ );
my $cfgfile          = $appbasename . '.cfg';
my $logfile_request  = $appbasename . '.Request.txt';
my $logfile_response = $appbasename . '.Response.xml';

my $appfilename = basename ( $0 );

my $cfgfile_found = 0;
read_Program_Configuration ();

# set STDOUT to configured terminal encoding
if ( $terminal_encoding ne $EMPTY ) {
  binmode ( STDOUT, ":encoding($terminal_encoding)" );
}

my $release = '0.4 - 2012/10/06';
printf { *STDOUT } ( "\n$appfilename - OpenStreetMap - OverPass-Api-Query, Rel. $release\n\n" );

# command line parameters
my $help   = $EMPTY;
my $prefix = $EMPTY;

# get the command line parameters
GetOptions ( 'help|h|?' => \$help, 'prefix=s' => \$prefix );

if ( $help || ( $#ARGV < 0 ) ) {
  show_help ();
}

if ( $prefix ne $EMPTY ) {
  $logfile_request  = $prefix . '.Request.txt';
  $logfile_response = $prefix . '.Response.xml';
}

# create an internet user agent
$ua = LWP::UserAgent->new;
$ua->agent   ( 'opaQuery/0.4' );
$ua->timeout ( $http_timeout );
if ( $http_proxy ne $EMPTY ) {
  $ua->proxy ( 'http', $http_proxy );
}

osm_request_service ();

printf { *STDOUT } ( "http status ...: %s\n", $osm_response->status_line );

$rc = 0;
if ( !$osm_response->is_success ) {
  $rc = 2;
}

if ( $display_response ) {
  printf { *STDOUT } ( "\n%s\n", $osm_response->decoded_content );
}

printf { *STDOUT } ( "\nosm request  : See logfile \"%s\" for details.\n", $logfile_request );
printf { *STDOUT } ( "osm response : See logfile \"%s\" for details.\n",   $logfile_response );

# return codes: 0=successful; 1=help screen; 2=not successful
exit ( $rc );


# -----------------------------------------
# Request a osm service - send http get/post request and decode xml response.
# -----------------------------------------
sub osm_request_service {
  my $osm_service_uri = $EMPTY;
  my $file_mode       = '+>';

  if ( $file_encoding ne $EMPTY ) {
    $file_mode = $file_mode . ':' . $file_encoding;
  }

  # open logfiles
  open ( my $LOGFILE_REQUEST,  $file_mode, $logfile_request )  or die ( "Error opening logfile \"$logfile_request\": $!\n" );
  open ( my $LOGFILE_RESPONSE, $file_mode, $logfile_response ) or die ( "Error opening logfile \"$logfile_response\": $!\n" );

  printf { $LOGFILE_REQUEST } ( "osm request:\n------------\n" );
  printf { $LOGFILE_REQUEST } ( "Timestamp .....: %s (localtime)\n", scalar localtime );
  printf { $LOGFILE_REQUEST } ( "Timestamp .....: %s (gmtime)\n", scalar gmtime );
  printf { $LOGFILE_REQUEST } ( "Configuration .: cfgfile = %s (%s)\n", $cfgfile, ( $cfgfile_found ? 'found' : 'not_found' ) );
  printf { $LOGFILE_REQUEST } ( "Configuration .: display_response = %s\n",             $display_response );
  printf { $LOGFILE_REQUEST } ( "Configuration .: terminal_encoding = %s (expected)\n", $terminal_encoding );
  printf { $LOGFILE_REQUEST } ( "Configuration .: file_encoding = %s\n",                $file_encoding );
  printf { $LOGFILE_REQUEST } ( "Configuration .: http_proxy = %s\n",                   $http_proxy );
  printf { $LOGFILE_REQUEST } ( "Configuration .: http_timeout = %s\n",                 $http_timeout );
  printf { $LOGFILE_REQUEST } ( "System ........: OSNAME = %s\n",                       $OSNAME );
  printf { $LOGFILE_REQUEST } ( "System ........: PERL_VERSION = %s\n",                 $PERL_VERSION );
  printf { $LOGFILE_REQUEST } ( "Application ...: name = %s\n",                         $appfilename );
  printf { $LOGFILE_REQUEST } ( "Application ...: release = %s\n",                      $release );
  printf { $LOGFILE_REQUEST } ( "Overpass QL ...: %s\n",                                $ARGV[ 0 ] );

  # build URI (osm request) (inclusive UTF8 escaping)
  $osm_service_uri = URI->new ( $osm_service_root );

  if ( $terminal_encoding ne $EMPTY ) {
    $osm_service_uri->query_param ( 'data', encode ( 'utf8', $ARGV[ 0 ] ) );
  }
  else {
    $osm_service_uri->query_param ( 'data', $ARGV[ 0 ] );
  }
  printf { $LOGFILE_REQUEST } ( "Service URI ...: %s\n", $osm_service_uri );

  # osm service
  $osm_response = $ua->get ( $osm_service_uri );

  printf { $LOGFILE_RESPONSE } ( "%s", $osm_response->decoded_content );

  printf { $LOGFILE_REQUEST } ( "\nosm response:\n-------------\n" );
  printf { $LOGFILE_REQUEST } ( "http status ...: %s\n", $osm_response->status_line );
  printf { $LOGFILE_REQUEST } ( "\nheaders .......: \n%s\n", $osm_response->headers_as_string );

  $rc = 0;
  if ( !$osm_response->is_success ) {
    $rc = 1;
  }

  # close logfiles
  close ( $LOGFILE_REQUEST );
  close ( $LOGFILE_RESPONSE );

  # 0=successful / 1=not successful
  return ( $rc );
}


# -----------------------------------------
# Show help and exit.
# -----------------------------------------
sub show_help {
  printf { *STDOUT }
    (   "Copyright (C) 2012 Klaus Tockloth <freizeitkarte\@googlemail.com>\n"
      . "This program comes with ABSOLUTELY NO WARRANTY. This is free software,\n"
      . "and you are welcome to redistribute it under certain conditions.\n"
      . "\n"
      . "Benutzung\n"
      . "=========\n"
      . "perl $appfilename [-prefix=String] \"Overpass-QL-String\"\n"
      . "perl $appfilename [-prefix=String] \'Overpass-QL-String\'\n"
      . "\n"
      . "Optionen:\n"
      . "-prefix = Ausgabedateipraefix (default = opaQuery)\n"
      . "\n"
      . "Beispiel (Windows)\n"
      . "==================\n"
      . "perl $appfilename \"node ['name'='Roxel'] (51.8, 7.4, 52.1, 7.8); out meta;\"\n"
      . "perl $appfilename \"node [name=Roxel] (51.8, 7.4, 52.1, 7.8); out meta;\"\n"
      . "\n"
      . "Beispiel (Linux, OS X) [bash]\n"
      . "=============================\n"
      . "perl $appfilename \'node [\"name\"=\"Roxel\"] (51.8, 7.4, 52.1, 7.8); out meta;\'\n"
      . "perl $appfilename \'node [name=Roxel] (51.8, 7.4, 52.1, 7.8); out meta;\'\n"
      . "\n"
      . "Dateien\n"
      . "=======\n"
      . "$logfile_request : Logdatei fuer die http-Anfrage (default)\n"
      . "$logfile_response : Logdatei fuer die xml-Antwort (default)\n"
      . "$cfgfile : Konfigurationsdatei\n"
      . "\n\n"
    );

  printf { *STDOUT }
    (   "Overpass-QL - grundlegende Sprachelemente\n"
      . "-----------------------------------------\n\n"
      . "Initialisierung\n"
      . "===============\n"
      . "[out:xml]            Ausgabe der Objekte im xml-Format (Default)\n"
      . "[out:json]           Ausgabe der Objekte im json-Format\n"
      . "[timeout:sekunden]   maximale Verarbeitungsdauer im Server in Sekunden (Default: 180)\n"
      . "[maxsize:byte]       maximaler RAM-Verbrauch im Server in Byte (Default: 512 MB; Max: 1024 MB)\n"
      . "\n"
      . "Zu selektierender Objekttyp\n"
      . "===========================\n"
      . "node   Knoten\n"
      . "way    Linie\n"
      . "rel    Relation\n"
      . "\n"
      . "Selektion nach Schluesselwerten\n"
      . "===============================\n"
      . "['key' = 'value']     Uebereinstimmung gegeben\n"
      . "['key' != 'value']    Uebereinstimmung nicht gegeben\n"
      . "['key']               Schluessel vorhanden (Wert irrelevant)\n"
      . "['key' !~ '.']        Schluessel nicht vorhanden (Sondersyntax)\n"
      . "['key' ~ 'RegExp']    regulaerer Ausdruck trifft zu\n"
      . "['key' !~ 'RegExp']   regulaerer Ausdruck trifft nicht zu\n"
      . "\n"
      . "Besondere Selektionen\n"
      . "=====================\n"
      . "(id)                  nur das Objekt mit angegebener ID\n"
      . "(user:'name')         nur Objekte des Users 'name'\n"
      . "(newer:'timestamp')   nur Objekte neuer als Timestamp (Beispiel: '2012-09-14T07:00:00Z')\n"
      . "\n"
      . "Logische Verknuepfungen\n"
      . "=======================\n"
      . "['key1' = 'value1'] ... ['keyN' = 'valueN']   logische Und-Verknuepfung\n"
      # . "['key1'] ... ['keyN']                         logische Und-Verknuepfung\n"
      . "['key' ~ 'value1|value2| ... |valueN']        logische Oder-Verknuepfung\n"
      . "\n" 
      . "Zu betrachtender Datenbereich\n"
      . "=============================\n"
      . "(sued, west, nord, ost)   rechteckige Box mit Koordinaten 'links unten + rechts oben'\n"
      . "\n"
      . "Behandlung der selektierten Objekte\n"
      . "===================================\n"
      . "out limit  Ausgabe von maximal 'limit' Objekten (Default = keine Beschraenkung)\n"
      . "out        Kurzform fuer: Ausgabe aller Objekte im xml-Format\n"
      . "\n"
      . "Detaillierung der selektierten Objekte\n"
      . "======================================\n"
      . "ids    nur Objekt-IDs\n"
      . "skel   Objekt-IDs + enthaltene Objekte\n"
      . "body   Objekt-IDs + enthaltene Objekte + Tags (Default)\n"
      . "meta   Objekt-IDs + enthaltene Objekte + Tags + Metadaten\n"
      . "\n"
      . "Sortierung der selektierten Objekte\n"
      . "===================================\n"
      . "asc   Sortierung nach IDs (default)\n"
      . "qt    Sortierung nach Quadtiles\n"
      . "\n"
      . "Beispiele - einfache Datenabfragen\n"
      . "==================================\n\n"
      . "\"[Initialisierung] ; Objekttyp [Selektion]           (Datenbereich)         ; Behandlung Detaillierung Sortierung ;\"\n"
      . "\"----------------- ; --------- ------------------    ---------------------- ; ---------- ------------- ---------- ;\"\n"
      . "\"                    node      ['name'='Gielgen']    (50.7, 7.1, 50.8, 7.2) ; out        meta                     ;\"\n"
      . "\"[out:json]        ; node      ['name'~'[gG]ielgen'] (50.7, 7.1, 50.8, 7.2) ; out        meta                     ;\"\n"
      . "\"[timeout:2000]    ; node      ['name'~'Gielgen\$']   (50.7, 7.1, 50.8, 7.2) ; out 3      body          qt         ;\"\n"
      . "\"                    way       (user:'toc-rox')      (50.7, 7.1, 50.8, 7.2) ; out        meta                     ;\"\n"
      . "\n"
      . "Beispiele - weitere Datenabfragen\n"
      . "=================================\n"
      . "\"[out:json] [timeout:1900]; node ['name'='Gielgen'] (50.7, 7.1, 50.8, 7.2); out meta;\"\n"
      . "\"way (user:'toc-rox')   (50.7, 7.1, 50.8, 7.2); out meta;\"\n"
      . "\"node (newer:'2012-10-01T13:30:00Z') (50.7, 7.1, 50.8, 7.2); out meta;\"\n"
      . "\n"
      . "Rekursionsoperatoren bei Knoten und Linien (node, way)\n"
      . "======================================================\n"
      . "<    Ausgabe aller Knoten, Linien und Relationen (nodes, ways, rels) in denen das Objekt vorkommt\n"
      . ">    Ausgabe aller enthaltenen Knoten (nodes)\n"
      . "\n"
      . "Rekursionsoperatoren bei Relationen (rel)\n"
      . "=========================================\n"
      . "<<   Ausgabe aller Relationen (rels) in denen die Relation vorkommt\n"
      . ">    Ausgabe aller enthaltenen Knoten und Linien (nodes, ways)\n"
      . ">>   Ausgabe aller enthaltenen Knoten, Linien und Relationen (nodes, ways, rels)\n"
      . "\n"
      . "Beispiele - Ausgabe der abhaengigen Objekte\n"
      . "===========================================\n"
      . "\"(node (530904873); <;); out;\"   Knoten 530904873 und alle Objekte (ways, rels) in denen der Knoten vorkommt\n"
      . "\"(way (42674611);   <;); out;\"   Linie 42674611 und alle Relationen (rels) in denen die Linie vorkommt\n"
      . "\"(rel (157770);    <<;); out;\"   Relation 157770 und alle Relationen (rels) in denen die Relation vorkommt\n"
      . "\n"
      . "Beispiele - Ausgabe der enthaltenen Objekte\n"
      . "===========================================\n"
      . "\"(way (42674611);   >;); out;\"   Linie 42674611 und alle Knoten (nodes) die darin enthalten sind\n"
      . "\"(rel (62779);      >;); out;\"   Relation 62779 und alle Knoten und Linien (nodes, ways) die darin enthalten sind\n"
      . "\"(rel (62779);     >>;); out;\"   Relation 62779 und alle Objekte (nodes, way, rels) die darin enthalten sind\n"
      . "\n"
      . "Beispiel - vollstaendige (Karten-)Daten eines Bereichs abfragen\n"
      . "===============================================================\n"
      . "\"(node (50.75, 7.15, 50.8, 7.2); <;); out meta;\"\n"
      . "\n"
      . "Objekte in der 'Naehe' eines Knoten abfragen\n"
      . "============================================\n"
      . "(around:radius)   Objekte im Radius von n Metern selektieren\n"
      . "\n"
      . "Beispiele - Objekte in der 'Naehe' abfragen\n"
      . "===========================================\n"
      . "\"node (619332904);  way (around:10000) ['name'~'Rostock']; out meta;\"\n"
      . "\"node (1794046057); way (around:1000)  ['leisure'='playground']; out meta;\"\n"
      . "\n"
      . "Beispiele - komplexere Abfragen\n"
      . "===============================\n"
      . "\"(node ['amenity'='police'] (51, 6, 52, 7); way ['amenity'='police'] (51, 6, 52, 7);); out meta;\"\n"
      . "\"(way ['admin_level'='7'] ['name'] (50, 6, 52, 8); rel ['admin_level'='7'] ['name'] (50, 6, 52, 8);); out;\"\n"
      . "\"(way ['name'~'Nationalpark'] (48, 6, 55, 15); rel ['name'~'Nationalpark'] (48, 6, 55, 15);); out meta;\"\n"
      . "\"node (user:Netzwolf) [natural=peak]; out meta;\"\n"
      . "\n"
      . "Beispiele - regulaere Ausdruecke\n"
      . "================================\n"
      . "['key' ~ 'value']           'value' enthalten\n"
      . "['key' !~ 'value']          'value' nicht enthalten\n"
      . "['key' ~ '^value']          'value' am Anfang enthalten\n"
      . "['key' ~ 'value\$']          'value' am Ende enthalten\n"
      . "['key' ~ '[Vv]alue']        'value' oder 'Value' enthalten\n"
      . "['key' ~ 'value1|value2']   'value1' oder 'value2' enthalten\n"
      . "\n"
      . "Datenabfragen mit negierten regulaeren Ausdruecken\n"
      . "==================================================\n"
      . "1. Primaere Selektion: alle Zielobjekte als Zwischenergebnis ermitteln\n"
      . "2. Sekundaere Selektion: regulaeren Ausdruck auf Zwischenergebnis anwenden\n"
      . "\n"
      . "Beispiele - negierte regulaere Ausdruecke\n"
      . "=========================================\n"
      . "\"node ['name'] ['name' !~ 'Roxel'] (51.8, 7.4, 52.1, 7.8); out meta;\"\n"
      . "\"rel ['de:regionalschluessel'] ['de:regionalschluessel' !~ '[0-9][0-9][0-9]'] (47.2, 5.8, 55.1, 15.1); out meta;\"\n"
      . "\"(way ['highway'='residential'] ['name' !~ '.'] (51.8, 7.5, 52.0, 7.8); >;); out meta;\"\n"
      . "\n"
      . "Beispiele - Datenbereiche der deutschen Bundeslaender\n"
      . "=====================================================\n"
      . "Baden-Wuerttemberg      (47.5, 7.4, 49.9, 10.6)\n"
      . "Bayern                  (47.2, 8.9, 50.6, 13.9)\n"
      . "Berlin                  (52.3, 13.0, 52.7, 13.8)\n"
      . "Brandenburg             (51.3, 11.1, 53.7, 14.9)\n"
      . "Bremen                  (52.9, 8.4, 53.7, 9.1)\n"
      . "Hamburg                 (53.5, 9.5, 53.8, 10.4)\n"
      . "Hessen                  (49.3, 7.6, 51.7, 10.3)\n"
      . "Mecklenburg-Vorpommern  (53.0, 10.4, 55.0, 14.4)\n"
      . "Niedersachsen           (51.2, 6.4, 54.2, 11.6)\n"
      . "Nordrhein-Westfalen     (50.2, 5.4, 52.6, 9.5)\n"
      . "Rheinland-Pfalz         (48.9, 6.1, 51.0, 8.5)\n"
      . "Saarland                (49.1, 6.3, 49.7, 7.4)\n"
      . "Sachsen                 (50.1, 11.8, 51.8, 15.1)\n"
      . "Sachsen-Anhalt          (50.9, 10.5, 53.2, 13.2)\n"
      . "Schleswig-Holstein      (53.3, 7.8, 55.1, 11.4)\n"
      . "Thueringen              (50.1, 9.8, 51.7, 12.7)\n"
      . "\n"
      . "Beispiele - Datenbereiche einiger Laender\n"
      . "=========================================\n"
      . "Deutschland             (47.2, 5.8, 55.1, 15.1)\n"
      . "Oesterreich             (46.3, 9.3, 49.1, 17.2)\n"
      . "Schweiz                 (45.8, 5.9, 47.9, 10.5)\n"
      . "Alpen                   (45.2, 5.5, 48.7, 16.7)\n"
      . "Italien                 (35.2, 6.6, 47.1, 19.2)\n"
      . "Frankreich              (42, -5, 51, 8)\n"
      . "Belgien                 (49.5, 2.3, 51.6, 6.4)\n"
      . "Niederlande             (50.7, 3.2, 53.6, 7.2)\n"
      . "Daenemark               (54.4, 7.7, 58.1, 15.5)\n"
      . "Schweden                (55, 10.5, 69, 24.2)\n"
      . "\n"
      . "Anmerkungen\n"
      . "===========\n"
      . "- siehe Sprachbeschreibung fuer weitere Features von Overpass-QL\n"
      . "- http://wiki.openstreetmap.org/wiki/Overpass_API/Language_Guide\n"
      . "- http://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL\n"
      . "- die Abfrage der Metadaten ist als ressourcenintensiv anzusehen\n"
      . "- die Aufloesung von Relationen ist als ressourcenintensiv anzusehen\n"
      . "- die Objektsortierung nach 'qt' ist performanter als die nach 'asc'\n"
      . "- die Datenausgabe erfolgt immer in der Reihenfolge nodes, ways, rels\n"
      . "- die Attribute der einleitenden Initialisierung sind kombinierbar\n"
      . "- bei Testabfragen kleine Datenbereiche (z.B. 0.1 * 0.1 Grad) verwenden\n"
      . "- Webseite zur Bestimmung des Datenbereichs: www.getlatlon.com\n"
      . "- aessere und innere Begrenzungszeichen unter Windows \" \'\' \"\n"
      . "- aessere und innere Begrenzungszeichen unter Linux   \' \"\" \'\n"
      . "- innere Begrenzungszeichen sind nur im Bedarfsfall erforderlich\n"
      . "\n"
    );
      
  exit ( 1 );
}


# -----------------------------------------
# Read program configuration from file.
# CodeSnippet from:
# - Perl Kochbuch, O'Reilly, 2. Auflage
# - 8.16 Konfigurationsdateien einlesen
# -----------------------------------------
sub read_Program_Configuration {
  my %config;

  if ( !( -s $cfgfile ) ) {
    return;
  }
  $cfgfile_found = 1;

  open ( my $CONFIG_FILE, '<', $cfgfile ) or die ( "Error opening cfgfile \"$cfgfile\": $!\n" );

  while ( <$CONFIG_FILE> ) {
    chomp ();    # no newline
    s/#.*//;     # no comments
    s/^\s+//;    # no leading white
    s/\s+$//;    # no trailing white
    next unless length ();    # anything left?
    my ( $var, $value ) = split ( /\s*=\s*/, $_, 2 );
    $config{ $var } = $value;
  }

  close ( $CONFIG_FILE );

  $display_response = $config{ display_response };
  # printf { *STDOUT } ( "display_response = <%s>\n", $display_response );

  $terminal_encoding = $config{ terminal_encoding };
  # printf { *STDOUT } ( "terminal_encoding = <%s>\n", $terminal_encoding );

  $file_encoding = $config{ file_encoding };
  # printf { *STDOUT } ( "file_encoding = <%s>\n", $file_encoding );

  $http_proxy = $config{ http_proxy };
  # printf { *STDOUT } ( "http_proxy = <%s>\n", $http_proxy );

  $http_timeout = $config{ http_timeout };
  # printf { *STDOUT } ( "http_timeout = <%s>\n", $http_timeout );

  return;
}
