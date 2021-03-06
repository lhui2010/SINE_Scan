use strict;
use Bio::SimpleAlign;
use Bio::AlignIO;
use File::Basename;
if(@ARGV<14){
	print "$0 <TE seq> <genome> <min copy number of TE in genome> <output dir> <extend size> <end size for termial check> <min_diff> <Sup_SAQ_LR> <Inf_SAQ_M> <Min_iden> <Max_dis> <block length> <sites percent> <cpu>\n";
	print "Be sure that blastdb of genome is formated.\n";
	exit(0);
}

my $genome=$ARGV[1];
my $workdir=$ARGV[3];
my ($sineseq,$sinedir)=(basename($ARGV[0]),dirname($ARGV[0]));
my $minCp=$ARGV[2];
my $script=dirname($0);
my $sizeFlank=$ARGV[4];
my $sizeEnd=$ARGV[5];
my $minDiff=$ARGV[6];
my $SupFL=$ARGV[7];
my $InfM=$ARGV[8];
my $minIden=$ARGV[9];
my $maxDis=$ARGV[10];
my $blockLen=$ARGV[11];
my $siteP=$ARGV[12];
my $CPU=$ARGV[13];

print "Command\n$0 ".join(" ",@ARGV)."\n\n";
print "Create working dir: $workdir\n";


print "\nMake directory for each TE:\n";
my $filtersines=$ARGV[0];
system "perl ./PL_pipeline/makeDirforTE.pl $filtersines  $workdir";
open in,$filtersines or die "$!\n";
my %map=();
my %chr=();
my $order=0;
while(<in>){
	if($_=~/>/){
		$_=~s/>//;
		my @a=split(/\|/,$_);
		my $w="$a[0],$a[1]";
		$map{$w}=$order;
		$chr{$a[0]}.="$a[1],";
		$order++;
	}
}
close in;
foreach my $i (keys%chr){
	my %pos_order=();
	my @a=split(/,/,$chr{$i});
	foreach my $j (@a){
		my @b=split(/-/,$j);
		if($b[0] > $b[1]){
			my $tmp=$b[0];
			$b[0]=$b[1];
			$b[1]=$tmp;
		}
		$j="$b[0]-$b[1]";
		$pos_order{$j}=$b[0];
	}
	$chr{$i}="";
	foreach my $j (sort {$pos_order{$a}<=>$pos_order{$b}} keys%pos_order){
		$chr{$i}.="$j,";
	}
	undef%pos_order;
}


open in,$genome or die "$!\n";
my %len=();
my $u;
while(<in>){
	chomp $_;
	if($_=~/>/){
		my @a=split(/\s+/,$_);
		$u=$a[0];
		$u=~s/>//;
		$len{$u}=0;
	}else{
		$len{$u}+=length($_);
	}
}
close in;

print "\nCheck copy number for TE clusters\n";
opendir DH,"$workdir" or die $!;
foreach my $name(sort {$a<=>$b} readdir DH){
	if(-d "$workdir/$name" && $name !~ /^\./){
		print "\n-----work on cluster $name-----\n";
		my $path="$workdir/$name";
		print "Its path is: $path\n";
		print "TE sequence: $path/$name.sine.fa\n";
		print "Scan genome using a file above: $path/$name.sine.genome.bls\n";
		system "/home/maohlzj/ncbi-blast-2.2.31+/bin/blastn -task blastn -db $genome -query $path/$name.sine.fa -max_target_seqs 100000 -evalue 1e-10 -dust no -out $path/$name.sine.genome.bls -num_threads $CPU -outfmt 6";
		open in,"$path/$name.sine.fa" or die "$!\n";
		my $query_length=0;
		while(<in>){
			chomp $_;
			if($_!~/^>/){
				$query_length+=length($_);
			}
		}
		close in;
		open fin,"<$path/$name.sine.genome.bls" or die $!;
		my %rank;
		my $cnt=0;#estimated copy number of the candidate TE
		while(<fin>){
			my @x=split(/\t/,$_);
			my $subject_length=abs($x[9]-$x[8])+1;
			if($x[9]-$x[8]<0){
				my $t=$x[8];
				$x[8]=$x[9];
				$x[9]=$t;
			}
			if($x[2]*$x[3]>=80*$query_length && $subject_length>=0.8*$query_length && $subject_length<=$query_length/0.8){ 
				my @a=split(/,/,$chr{$x[1]});
				foreach my $j (@a){
					my @A=split(/-/,$j);
					if($A[0] > $x[9]){		
						last;
					}
					my $R=($x[8]-$A[1])*($x[9]-$A[0]);
					if($R < 0){
						my $B="$x[1],$j";
						my $DIR="$workdir/$map{$B}";
						if(-d $DIR && exists $map{$B} && $map{$B} != $name){
							system "rm -rf $DIR";
							print "$name, it deletes $DIR\n";
							$chr{$x[1]}=~s/$j,//;
						}
					}
				}	
				if($x[6]==1 && $x[7]==$query_length && $x[8]>$sizeFlank && $x[9]+$sizeFlank<$len{$x[1]}){
					my $number=$cnt;
					my $iden=$x[2]*$x[3]/100;
					$rank{$iden}{$_}=$number;
					++$cnt;
				}
			}
		}
		close fin;
		print "Find $cnt good hits within $sizeFlank bp flaking sequences.\n";
		if($cnt<$minCp){
			print "Cluster $name has $cnt good hits in genome, less than the cutoff value $minCp: stop analyse this cluster!\n";
#			unlink glob "$path/* $path/.*";
#			rmdir $path;
			system "rm $path/$name.sine.genome.bls";
			next;
		}
		open fout,">$path/$name.sine.genome.filter" or die $!;
		my $p=0;
		my $flag=1;
		foreach my $identity(reverse sort {$a<=>$b} keys %rank){###identical percentage of query
			if($flag==0){
				last;
			}
			foreach my $line(reverse sort {$rank{$identity}{$a}<=>$rank{$identity}{$b}} keys%{$rank{$identity}}){ ###identical percentage of subject
				if($p == 35){
					last;
				}else{
					print fout "$line";
					$p++;
				}
			}	
		}
		close fout;

		print "Extract $p best hits: $path/$name.sine.extendseq\n";
		system "perl ./PL_pipeline/extendseq.pl $path/$name.sine.genome.filter $genome $sizeFlank >$path/$name.sine.extendseq";

#####check end ,TSD-finder then output a good seed sequence for next-step (annotation)############
###step first: checkend and TSD-finder#######
		my $scores=`perl ./PL_pipeline/New_checkboundaryAndTSD.pl $path/$name.sine.extendseq $sizeFlank $sizeEnd $minDiff $SupFL $InfM $minIden $maxDis $blockLen $siteP`;
		system "/home/maohlzj/sine_te/softwares/muscle -in $path/$name.sine.extendseq -out $path/$name.sine.extendseq.msa.fasta -maxiters 1 -diags -quiet";
		chomp $scores;
		my @score=split(/,/,$scores);
		if(@score == 1 && $scores == 1){
			print "TE ends and TSD found in proper region.\n";
		}elsif(@score == 3){
			print "$path : cannot find good TE ends: H=$score[1],L=$score[0],R=$score[2]\n";
			print "This cluster may only represent internal part of repeats. stop analyse this cluster\n";
			system "rm $path/$name.sine.genome.bls $path/$name.sine.genome.filter";
#			unlink glob "$path/* $path/.*";
#			rmdir $path;
			next;
		}elsif($scores == -1){
			print "$path : cannot find proper TE ends.\n";
		}elsif($scores == 2){
			print "$path : 5' and 3' ends are inverted repeats, or it has 'TG-CA' structure or it has 'TC-CTRR-T' structure. Category this as a MITE or a helitron or solo-LTR.\n";
		}else{
			print "$path : cannot find good TSDs.\n";
		}
###step second: self-do manual check and build a good sequence for next-step annotation########
		print "Align these top hits: $path/$name.sine.extendseq.msa.fasta\n";
		print "You could manually evaluate alignment ends using the $path/$name.sine.extendseq.SixtyFiftySixty.msa.fasta\n";
		print "cluster $name is ready for inspection\n";
		if($scores == 1){
			system "perl ./PL_pipeline/betterSeq-seeds.pl $path/$name.sine.extendseq";
			my $annotation=basename($workdir).".for_annotation.fa";########annotation file in workdir
			if(-e "$path/$name.sine.for_annotation.fa"){
				system "cat $path/$name.sine.for_annotation.fa >>$workdir/$annotation";
				system "rm $path/$name.sine.for_annotation.fa";
			}
		}
		system "rm $path/$name.sine.genome.* ";
	}
}
closedir DH;
print "\nDone.\n";

