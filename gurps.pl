#!/usr/bin/perl


# ----------------------------------------------------------------------
#
# gurps.pl
#
# 2025-04-25: Update to perl 5.40.0 and lualatex with TeXLive 2025
#
# Read in XML file and convert to perl structure using XML::Simple.
#
# ----------------------------------------------------------------------

use 5.40.0;
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);
use Time::localtime;
use XML::Simple;
use Perl6::Slurp;
use JSON;
use Encode;

# ----------------------------------------------------------------------
#
# Update
#
# ----------------------------------------------------------------------

sub Update {
    my ($character) = @_;

    my %points;
    my %stats;


    my $stat_map = {
	'DX' => {
	    'cost' => 20,
	    'base' => 10,
	},
	'IQ' => {
	    'cost' => 20,
	    'base' => 10,
	},
	'ST' => {
	    'cost' => 10,
	    'base' => 10,
	},
	'HT' => {
	    'cost' => 10,
	    'base' => 10,
	},
	'HP' => {
	    'inc' => 2,
	    'base' => 'ST',
	},
	'FT' => {
	    'inc' => 3,
	    'base' => 'HT',
	},
	'Per' => {
	    'inc' => 5,
	    'base' => 'IQ',
	}, 
	'Will' => {
	    'inc' => 5,
	    'base' => 'IQ',
	},
	'Speed' => {
	    'inc' => 20,
	    'base' => '(DX+HT)/4',
	}, 
	'Move' => {
	    'inc' => 5,
	    'base' => 'int(Speed)',
	}, 
   };
    
    if (!exists($character->{'stats'}))
    {
	print STDERR "No <stats> found.\n";
	exit(1);
    }
    
    my $sum = 0;

# --------------------
# Stats
# --------------------

    my $stats = $character->{'stats'}->{'stat'};
    my @used;

     for my $s ("DX", "IQ", "ST", "HT", "HP", "Per", "Speed", "Move", "Will", "FT")
     {
 	my $t = $stat_map->{$s};
 	if (!exists($stats->{$s}))
 	{
 	    $stats->{$s} = {
 		'name' => $s,
 	    };
 	}
 	my $stat = $stats->{$s};
 	my $base = $stats->{$s}->{'base'} = $t->{'base'};

 	map {
 	    my $n = $_;
 	    my $v = $stats->{$n}->{'value'};
 	    $base =~ s:$n:$v:;
 	} @used;

 	$base = eval($base);

 	$stat->{'value'} = $base if (!($stat->{'value'}));

 	my $cost = ($stat->{'value'} - $base) * ($t->{'cost'} // 0);
 	printf "%s: %f (%f) [%f]\n", $s, $stat->{'value'}, $base, $cost;
 	push(@used, $s);
 	$sum += $cost;
	$stat->{points} = $cost;
     }

    $character->{'stats'}->{points} = $sum;
    $points{"stats"} = $sum;

# --------------------
# Advantages, Disadvantages & Quirks
# --------------------

    if (my $disadvantages = $character->{disadvantages})
    {
	my $points = 0;
	for my $disadvantage (@{$disadvantages->{disadvantage}})
	{
	    if (!exists($disadvantage->{points}))
	    {
		printf STDERR "Disadvantage %s does not have the attribute 'points'.\n", $disadvantage->{name};
		exit 1;
 	    }
 	    $points += $disadvantage->{points};	    
 	}
 	$points{"disadvantages"} = -$points;
	$disadvantages->{points} = $points;
    }

    if (my $advantages = $character->{advantages})
    {
	my $points = 0;
	for my $advantage (@{$advantages->{advantage}})
	{
	    if (!exists($advantage->{points}))
	    {
		printf STDERR "Advantage %s does not have the attribute 'points'.\n", $advantage->{name};
		exit 1;
 	    }
 	    $points += $advantage->{points};
 	}
 	$points{"advantages"} = $points;
	$advantages->{points} = $points;
    }

    if (my $quirks = $character->{quirks})
    {
	my $points = 0;
	for my $b (@{$quirks->{quirk}})
	{
	    if (!$b->{description})
 	    {
 		printf STDERR "Quirk %s does not have the attribute 'description'.\n", $b->{name};
 		exit 1;
 	    }
 	    $points += 1;
 	}	
 	$quirks->{"points"} = $points;
 	$points{"quirks"} = -$points;
    }

# --------------------
# Skills
# --------------------

    my $skill_map = from_json(slurp('skills.js'));
    
    if (my $skills = $character->{skills})
    {
	for my $skill (@{$skills->{skill}})
	{
	    if (!$skill->{"name"})
 	    {
 		print STDERR "Found skill with no name.\n";
 		exit 1;
 	    }
	    
	    my $name = $skill->{name};
	    my $points = $skill->{points};

 	    if (!exists $skill_map->{$name})
 	    {
 		print STDERR "No skill map entry for skill $name.\n";
 		exit 1;
 	    }

	    my $skill_def = $skill_map->{$name};
	    my ($skill_stat, $skill_difc) = split(m:/:, $skill_def->{'t'});
	    my $diff;
	    
	    if ($skill_difc eq "V")
	    {
		if (!$skill->{"difficulty"})
		{
 		    print STDERR "Skill $name has variable difficulty and no difficulty defined.\n";
 		    exit 1;
 		}
 		$diff = $skill->{"difficulty"};
 	    }
 	    my $diff_map = {
 		'E' => 0,
 		'A' => -1,
 		'H' => -2,
 	    };

 	    my $cost_map = {
 		1 => 0,
 		2 => 1,
 		4 => 2,
 	    };

 	    my $level;

 	    if ($points > 4)
 	    {
 		if ($points/4 != int($points/4))
 		{
 		    printf STDERR "Incorrect points value for skill $skill [$points]\n";
 		    exit 1;
 		}
 		$level = $points/4 + 1;
 	    }
 	    else
 	    {
 		if (exists($cost_map->{$points}))
 		{
 		    $level = $cost_map->{$points};
 		}
 		else
 		{
 		    printf STDERR "Points $points not correct.\n";
 		}
 	    }

# --------------------
# Do Tech Level checking
# --------------------

 	    if (exists($skill_def->{'tl'}))
 	    {
 		my @tl = split(/;/, $skill_def->{'tl'});
 		if (!$skill->{'tl'})
 		{
 		    printf STDERR "Skill $name has Tech Level but no tech level set.\n";
 		    exit 1;
 		}
 	    }
 	    if (exists($skill->{"tl"}) && !exists($skill_def->{'tl'}))
 	    {
 		printf STDERR "Skill $name has Tech level set but skill does not require specific tech level.\n";
 		exit 1;
 	    }

 	    $diff = $diff_map->{$skill_difc} // 0;

 	    my $value = $stats->{$skill_stat}->{'value'};
 	    printf "[$skill_stat/$skill_difc] $name p=%d (%+d)\n", $points, $value + $level + $diff;

 	    $skill->{stat} = $skill_stat;
	    $skill->{diff} = $skill_difc;
 	    $skill->{level} = $level + $diff;
 	    $skill->{value} = $value + $level + $diff;
	    $points{"skills"} += $points;
	}
	$skills->{points} = $points{"skills"};
    }    
    if (my $basics = $character->{basics})
    {
 	my $total_points = 0;
 	map {
 	    $total_points += $points{$_};
 	} keys(%points);
 	$basics->{points} = $total_points;
    }
}

# ----------------------------------------------------------------------
#
# TeXOutput
#
# ----------------------------------------------------------------------
sub TeXOutput {
    my $character = $_[0];
    my $stream = $_[1];
    my $figure = $_[2];

# --------------------
# Start TeX output
# --------------------

    if ($figure == 0)
    {
	print $stream "\\documentclass[a4paper]{article}\n";
	print $stream "\\usepackage{gurps}\n";
	print $stream "\\begin{document}\n";
    }
    else
    {
	print $stream "\\begin{figure}\n";
    }

    print $stream "\\begin{multicols}{2}\n";
    print $stream "\\gtitle\n";

# --------------------
# Do Basic stuff
# --------------------

#    print $stream "\\begin{minipage}{\\columnwidth}\n";
    print $stream "\\setlength\\parskip{2pt}\n";

    my $basics = $character->{basics};
    my $date = strftime("%d %B %Y", @{localtime(time())});
    my $points = $basics->{"points"} // 0;

    printf $stream "\\ghead{Name}{%s}\n", $basics->{"name"};
    printf $stream "\\ghead{Alias}{%s}\n", $basics->{"alias"} if ($basics->{alias});
    printf $stream "\\ghead{Player}{%s}\n", $basics->{"player"} // "";
    printf $stream "\\ghead{Date Created}{%s}\n", $date;
    printf $stream "\\ghead{Total Points}{%s}\n", $points;
    printf $stream "\\gbox{Apperance}{%s}\n", $basics->{apperance};

# --------------------
# Do Story
# --------------------

    printf $stream "\\gbox{Story}{%s}\n\n", $character->{story} if ($character->{story});

#    printf $stream "\\end{minipage}\n\n";

    
# --------------------
# Do Stats
# --------------------

    my $stats = $character->{stats}->{stat};
    my $st_map = {};
    my $st_points = {};

    for my $s (qw/ST DX IQ HT Move Speed FT HP/)
    {
	if ($stats->{$s})
	{
	    $st_map->{$s} = $stats->{$s}->{value};
	    $st_points->{$s} = $stats->{$s}->{points};
	}
    }

    my $enc = 0;

    printf $stream "\\begin{statstbl}{}\\\n";
    printf $stream "\\textbf{Stats (%d)} \\\\\n", $character->{stats}->{points};
    printf($stream "%d & \\Large\\textsc{st} %d & %d & \\Large\\textsc{dx} %d \\\\\n",
	   $st_points->{"ST"},
	   $st_map->{"ST"},
	   $st_points->{"DX"},
	   $st_map->{"DX"}
	);
    printf($stream "%d & \\Large\\textsc{iq} %d & %d & \\Large\\textsc{ht} %d \\\\\n",
	   $st_points->{"IQ"},
	   $st_map->{"IQ"},
	   $st_points->{"HT"},
	   $st_map->{"HT"}
	);
    printf $stream "\\end{statstbl}\n\n";

    printf $stream "\\begin{sectbl}{}\n";
    printf $stream "FATIGUE & HIT POINTS \\\\ %d & %d \\\\\n", $st_map->{FT}, $st_map->{HP};
    printf $stream "BASIC SPEED & MOVE \\\\ %4.2f & %d \\\\\n", $st_map->{'Speed'}, $st_map->{'Move'};
    printf $stream "\\end{sectbl}\n\n";

    printf $stream "\\begin{enctbl}{} \n";
    printf $stream "\\textbf{Encumberance} \\\\ \n";
    printf $stream "None (0) = 2 \$\\times\$ ST = 2 \$\\times\$ %d = %d \\\\\n", $st_map->{'ST'}, 2 * $st_map->{'ST'};
    printf $stream "None (1) = 4 \$\\times\$ ST = 4 \$\\times\$ %d = %d \\\\\n", $st_map->{'ST'}, 4 * $st_map->{'ST'};
    printf $stream "None (2) = 6 \$\\times\$ ST = 6 \$\\times\$ %d = %d \\\\\n", $st_map->{'ST'}, 6 * $st_map->{'ST'};
    printf $stream "None (3) = 12 \$\\times\$ ST = 12 \$\\times\$ %d = %d \\\\\n", $st_map->{'ST'}, 12 * $st_map->{'ST'};
    printf $stream "None (4) = 20 \$\\times\$ ST = 20 \$\\times\$ %d = %d \\\\\n", $st_map->{'ST'}, 20 * $st_map->{'ST'};
    printf $stream "\\end{enctbl}\n\n";

# --------------------
# Advantages
# --------------------

    if (my $advantages = $character->{advantages})
    {
	printf $stream "\\begin{advtbl}{}\n";
	printf $stream "\\textbf{Advantages (%d)} \\\\ \n", $advantages->{points};

	for my $a (sort({$a->{name} cmp $b->{name}} @{$advantages->{advantage}}))
	{
	    printf $stream "%d & %s \\\\\n", $a->{points}, $a->{name};
	}
     	printf $stream "\\end{advtbl}\n\n";
    }

# --------------------
# Disadvantages
# --------------------

    if (my $disadvantages = $character->{disadvantages})
    {
	printf $stream "\\begin{advtbl}{}\n";
	printf $stream "\\textbf{Disadvantages (%d)} \\\\ \n", $disadvantages->{points};

	for my $d (sort({$a->{name} cmp $b->{name}} @{$disadvantages->{disadvantage}}))
	{
	    if ($d->{'description'})
     	    {
     		printf($stream "%d & %s (\\small \\emph{%s}) \\\\\n",
     		       $d->{points},
     		       $d->{name},
     		       $d->{description},
     		       );
     	    }
     	    else
     	    {
     		printf($stream "%d & %s \\\\\n",
     		       $d->{points},
     		       $d->{name});
     	    }
     	}
	printf $stream "\\end{advtbl}\n\n";
    }

# --------------------
# Quirks
# --------------------

    if (my $quirks = $character->{quirks})
    {
	printf $stream "\\begin{advtbl}{}\n";
	printf $stream "\\textbf{Quirks (%d)} \\\\ \n", $quirks->{points};

	for my $q (@{$quirks->{quirk}})
	{
	    printf($stream "%d & %s \\\\\n", 1, $q->{description});
	}
	printf $stream "\\end{advtbl}\n\n";
    }

# --------------------
# Do Skills
# --------------------

    if (my $skills = $character->{skills})
    {
    
	printf $stream "\\begin{skillstbl}{} \n";
	printf $stream "\\textbf{Skills (%s)} \\\\\n", $skills->{points};
	
	for my $s (@{$character->{skills}->{skill} || []})
	{
	    my $level = $s->{level};
     	    my $stat = $s->{stat} . "/". $s->{diff} .
     		($level == 0 ? "" :
     		 (($level > 0) ? 
     		  " + " .$level  :
     		  " - " . -$level));

	    my $tl = $s->{"tl"} ? ("/" . $s->{"tl"}): "";
	    
	    my $spec = $s->{special} ? sprintf("\\emph{(%s)}", $s->{special}) : "";
					       
	    printf($stream "%d & %s%s %s & %s & %d \\\\\n",
     		   $s->{points},
     		   $s->{name},
     		   $tl,
     		   $spec,
     		   $stat,
     		   $s->{value});
	}
	printf $stream "\\end{skillstbl}\n\n";
    }

# --------------------
# Finish TeX output
# --------------------

    print $stream "\\end{multicols}\n";

    if ($figure)
    {
	print $stream "\\end{figure}\n";
    }
    else
    {
	print $stream "\\end{document}\n";
    }
}

# ----------------------------------------------------------------------
#
# M A I N
#
# ----------------------------------------------------------------------

sub main {
    my $infile = undef;
    my $outfile = undef;
    my $figure = 0;
    GetOptions(
	'in=s' => \$infile,
	'out=s' => \$outfile,
	'figure' => \$figure,
	);

    # --------------------
    # Parse input file
    # --------------------

    if (!defined($infile))
    {
	printf STDERR "$0: --in=<in file> --out=<out file>\n";
	exit 1;
    }

    if (! -e $infile)
    {
	print STDERR "$0: $infile does not exist.\n";
	exit 1;
    }
    if (! -f $infile)
    {
	print STDERR "$0: $infile is not a file.\n";
	exit 1;
    }

    my $xml = slurp($infile);
    
    my $doc = XMLin($xml, KeepRoot => 1,  KeyAttr => { 'stat' => 'name' }, ForceArray => [ 'quirk', 'advantage', 'disadvantage' ]);

    # --------------------
    # Sanity check
    # --------------------
    
    my $character = $doc->{'character'};
    
    if (!defined($character))
    {
	print STDERR "Document Root not 'character'.\n";
	exit 1;
    }

    if (!exists($character->{'system'}))
    {
	print STDERR "<character> has not attribute 'system'.\n";
	exit 1;
    }
    
    if ($character->{'system'} ne "GURPS")
    {
	print STDERR "Character is not GURPS.\n";
	exit 1;
    }

    # --------------------
    # Update document
    # --------------------
    
    &Update($character);

    # --------------------
    # Output to TeX
    # --------------------
    
    if (!defined($outfile))
    {
	print "No output set.  Exiting with success.\n";
	exit 0;
    }

    my $stream;
    
    if (!open($stream, ">:utf8", "$outfile"))
    {
	print STDERR "$0: failed to open $outfile for writing: $!\n";
	exit(1);
    }

    &TeXOutput($character, $stream, $figure);
    close($stream);
}

&main();
