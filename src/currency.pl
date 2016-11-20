#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use Getopt::Std;

my $currenciesList = {
	"USD" => "169",
	"EUR" => "196",
	"CAD" => "29",
	"RU"  => "209"
};

use constant URL_FORMAT => "https://bank.gov.ua/control/uk/curmetal/currency/search?formType=searchPeriodForm&time_step=daily&currency=CC_CODE&periodStartTime=START_DATE&periodEndTime=END_DATE&outer=OUT_FORMAT&execute=%D0%92%D0%B8%D0%BA%D0%BE%D0%BD%D0%B0%D1%82%D0%B8";

my %opts;
getopts("hs:e:c:", \%opts);

my $useXML = undef;
if (eval "require XML::Simple")
{
	$useXML = 1;
	print "use XML::Simple\n";
}
else
{
	print "could not find XML::Simple; parse HTML\n";
}

sub showHelp
{
	my $error = shift;
	
	print "ERROR: $error\n" if ($error);
	print "Usage: ./currency.pl -s 2015-10-10 -c USD -e 2016-10-20\n"
		. "\t -h      show this help\n"
		. "\t -s      required start date in format yyyy-mm-dd\n"
		. "\t -e      optional end date in format yyyy-mm-dd (should be less than start date\n"
		. "\t -c      required currency; valid values: " . join(",", keys(%$currenciesList)) . "\n";
	exit(0);
}

sub validateInput
{
	my ($startDate, $endDate, $currency) = @_;

	my $dateReg = qr/^\d\d\d\d-\d\d-\d\d$/;

	showHelp("Require startDate")              if (!$startDate);
	showHelp("Require currency")               if (!$currency);
	showHelp("Invalid startDate format")       if ($startDate !~ $dateReg);
	showHelp("Invalid endDate format")         if ($endDate !~ $dateReg);
	showHelp("Invalid currency")               if (! exists($currenciesList->{$currency}));
	showHelp("startDate should be <= endDate") if ($startDate gt $endDate);

	return 1;
}

sub parseXml
{
	my $str = shift;
	my $struct = XML::Simple->new()->XMLin($str);
	return ref($struct) ? $struct->{"currency"} : [];
}

sub parseHtml
{
	my $str = shift;

	my $sub = sub {
		my ($openTag, $value, $closeTag) = @_;
		$value =~ s/\n|\r\n|\s+//g;
		return join("", $openTag, $value, $closeTag);
	};

	$str =~ s/(<(td).*?>)([^<]+)(<\/?\2>)/$sub->($1, $3, $4)/mgse; # glue empty lines inside "td" tags

	my @struct = ();
	my @fields = qw/date time number_of_units exchange_rate/;
	my $fieldsCnt = scalar(@fields);
	my $i = 0;
	my $subStruct;

	foreach (split(/\n|\r\n/, $str))
	{
		if (/<table.*id=.results0./ .. /<\/table>/)
		{
			if (/<tr>/)
			{
				$subStruct = {};
				$i = 0;
				next;
			}

			if (/<td/)
			{
				my ($value) = $_ =~ /<td.*?>([^<]+)<\/td>/s;
				chomp($value);
				if (exists($fields[$i]))
				{
					$subStruct->{$fields[$i]} = $value;
					$i++;
				}
				next;
			}

			if (/<\/tr>/)
			{
				push(@struct, $subStruct);
				next;
			}
		}	
	}

	return \@struct;
}

sub getReport
{
	my $struct = shift;
	my (@report) = ("\n\nStart Report\n");

	my $format = "%-14s|%-10s|%-10s";

	push(@report, sprintf($format, "Date", "N# Units", "Rate"));

	foreach (@$struct)
	{
		push(@report, sprintf($format, $_->{"date"}, $_->{"number_of_units"},
			$_->{"exchange_rate"}));
	}

	return join("\n", @report) . "\n";
}

sub fetchFromNbu
{
	my ($startDate, $endDate, $currency) = @_;

	my ($year, $month, $day) = split(/-/, $startDate);
	my $startDateFormated = join(".", reverse(split(/-/, $startDate)));
	my $endDateFormated = join(".", reverse(split(/-/, $endDate)));

	my $currencyCode = $currenciesList->{$currency};
	my $responseFormat = $useXML ? "xml" : "table";

	my $url = URL_FORMAT;
	$url =~ s/START_DATE/$startDateFormated/;
	$url =~ s/END_DATE/$endDateFormated/;
	$url =~ s/CC_CODE/$currencyCode/;
	$url =~ s/OUT_FORMAT/$responseFormat/;

	my $agent = LWP::UserAgent->new();
	my $response = $agent->get($url);

	if ($response->is_success) 
	{
		my $body = $response->decoded_content;
		return $useXML ?
			parseXml($body) :
			parseHtml($body);
	}
	else
	{
		warn("Could not load $url; error: " . $response->status_line);
		return undef;
	}
}

sub main
{
	showHelp() if (exists($opts{"h"}) && $opts{"h"});

	my $startDate = exists($opts{"s"}) ? $opts{"s"} : undef;
	my $endDate =   exists($opts{"e"}) ? $opts{"e"} : $startDate;
	my $currency =  exists($opts{"c"}) ? $opts{"c"} : undef;

	validateInput($startDate, $endDate, $currency);
	my ($result) = fetchFromNbu($startDate, $endDate, $currency);

	if (ref($result) eq ref([]) && scalar(@$result) > 0)
	{
		print getReport($result);
	}
	else
	{
		print "Empty report\n";
	}
}

eval { main() };
print "Something wrong: $@\n" if ($@);
