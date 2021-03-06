# before I run I set up my PERL5LIB doing 2 things:  ********************************************************
# PERL5LIB=/nfs/panda/ensemblgenomes/development/tapanari/eg-ena/modules
# source /nfs/panda/ensemblgenomes/apis/ensembl/81/setup.sh

# or simply:
#PERL5LIB=/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-variation/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-rest/lib:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-production/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-pipeline/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-hive/modules:/nfs/production/panda/ensemblgenomes/development/tapanari/ensemblgenomes-api/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-funcgen/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-compara/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl-analysis/modules:/nfs/production/panda/ensemblgenomes/apis/ensembl/81/ensembl/modules:/nfs/production/panda/ensemblgenomes/apis/bioperl/run-stable:/nfs/production/panda/ensemblgenomes/apis/bioperl/stable:/nfs/panda/ensemblgenomes/development/tapanari/eg-ena/modules

# example run:
# perl track_hub_creation_and_registration_pipeline.pl -username tapanari -password testing -local_ftp_dir_path /homes/tapanari/public_html/data/test2  -http_url http://www.ebi.ac.uk/~tapanari/data/test2 > output
# perl track_hub_creation_and_registration_pipeline.pl -username tapanari2 -password testing2 -local_ftp_dir_path /nfs/ensemblgenomes/ftp/pub/misc_data/.TrackHubs/ena_warehouse_meta  -http_url ftp://ftp.ensemblgenomes.org/pub/misc_data/.TrackHubs/ena_warehouse_meta 1> output 2>errors

# third Registry account for testing: username: tapanari2 , password : testing2

use strict ;
use warnings;

use HTTP::Tiny;
use Getopt::Long;
use JSON;
use DateTime;   
use Date::Manip;
use Time::HiRes;
use LWP::UserAgent;
use HTTP::Request::Common;
use Time::Piece;


my $registry_user_name ;
my $registry_pwd ;
my $ftp_local_path ; # ie. ftp://ftp.ensemblgenomes.org/pub/misc_data/.TrackHubs
my $http_url ;  # ie. /nfs/ensemblgenomes/ftp/pub/misc_data/.TrackHubs;

my $from_scratch; 
my $use_ena_warehouse_meta;

my $start_time = time();

GetOptions(
  "username=s" => \$registry_user_name ,
  "password=s" => \$registry_pwd,
  "local_ftp_dir_path=s" => \$ftp_local_path,
  "http_url=s" => \$http_url,   # string
  "do_track_hubs_from_scratch"  => \$from_scratch , # flag
  "use_ena_warehouse_metadata"  => \$use_ena_warehouse_meta #flag
);
   
my $http = HTTP::Tiny->new();
my $registry_server = "http://193.62.54.43:5000";


my $date_string = localtime();
print "* Started running the pipeline on:\n";
print "Local date,time: $date_string\n";


print "\n* Ran this pipeline:\n\n";
print "perl track_hub_creation_and_registration_pipeline.pl  -username $registry_user_name -password $registry_pwd -local_ftp_dir_path $ftp_local_path -http_url $http_url";
if($from_scratch){
  print " -do_track_hubs_from_scratch";
}

if($use_ena_warehouse_meta){
  print " -use_ena_warehouse_metadata";
}

print "\n";

print "\n* I am using this ftp server to eventually build my track hubs:\n\n $http_url\n\n";
print "* I am using this Registry account:\n\n user:$registry_user_name \n password:$registry_pwd\n";

$| = 1;  # it flashes the output

my %studies_last_run_of_pipeline = %{give_all_Registered_track_hubs()};
my %distinct_runs_before_running_pipeline;

foreach my $hub_name (keys %studies_last_run_of_pipeline){
  
  map { $distinct_runs_before_running_pipeline{$_}++ } keys %{give_all_runs_of_study_from_Registry($hub_name)};
}

print "\n*Before starting running the updates, there were in total ". scalar (keys %studies_last_run_of_pipeline). " track hubs with total ".scalar (keys %distinct_runs_before_running_pipeline)." runs registered in the Track Hub Registry under this account.\n";

$| = 1;  # it flashes the output

if (! -d $ftp_local_path) {
  print "\nThis directory: $ftp_local_path does not exist, I will make it now.\n";
  `mkdir $ftp_local_path`;
}

my @study_ids_not_yet_in_ena;

if ($from_scratch){

  print "\n ******** deleting all track hubs registered in the Registry under my account\n\n";  
  my $delete_script_output = `perl delete_registered_trackhubs.pl -username $registry_user_name -password $registry_pwd -study_id all`  ; 
  print $delete_script_output;

  if(scalar keys (%studies_last_run_of_pipeline) ==0){

    print "there were no track hubs registered \n";
  }

  $| = 1;  # it flashes the output

  print "\n ******** deleting everything in directory $ftp_local_path\n\n";

  my $ls_output = `ls $ftp_local_path`  ;

  if($? !=0){ # if ls is successful, it returns 0
 
    die "I cannot see contents of $ftp_local_path(ls failed) in script: ".__FILE__." line: ".__LINE__."\n";

  }

  if(!$ls_output){  # check if there are files inside the directory

    print "Directory $ftp_local_path is empty - No need for deletion\n";

  } else{ # directory is not empty

    `rm -r $ftp_local_path/*`;  # removing the track hub files in the ftp server

    if($? !=0){ # to see if the rm was successful
 
      print STDERR "ERROR: failed to remove contents of dir $ftp_local_path in script: ".__FILE__." line: ".__LINE__."\n";

    }else{

      print "Successfully deleted all content of $ftp_local_path\n";
    }

  }
 
}

my $ens_genomes_plants_rest_call = "http://rest.ensemblgenomes.org/info/genomes/division/EnsemblPlants?content-type=application/json"; # to get all ensembl plants names currently

my @array_response_plants_assemblies = @{getJsonResponse($ens_genomes_plants_rest_call)};  


my %assName_assAccession;
my %assAccession_assName;
my %ens_plant_names;

# response:
#[{"base_count":"479985347","is_reference":null,"division":"EnsemblPlants","has_peptide_compara":"1","dbname":"physcomitrella_patens_core_28_81_11","genebuild":"2011-03-JGI","assembly_level":"scaffold","serotype":null,
#"has_pan_compara":"1","has_variations":"0","name":"Physcomitrella patens","has_other_alignments":"1","species":"physcomitrella_patens","assembly_name":"ASM242v1","taxonomy_id":"3218","species_id":"1",
#"assembly_id":"GCA_000002425.1","strain":"ssp. patens str. Gransden 2004","has_genome_alignments":"1","species_taxonomy_id":"3218"},


foreach my $hash_ref (@array_response_plants_assemblies){

  my %hash = %{$hash_ref};

  $ens_plant_names {$hash {"species"}} = 1; # there are 39 Ens plant species at the moment Nov 2015

  if(! $hash{"assembly_id"}){  # some species don't have assembly id, ie assembly accession, 
    #  3 plant species don't have assembly accession: triticum_aestivum, oryza_longistaminata and oryza_rufipogon 

    $assName_assAccession  {$hash{"assembly_name"}} =  "0000";
    next;
  }

  $assName_assAccession  {$hash{"assembly_name"} } = $hash{"assembly_id"};
  $assAccession_assName  {$hash{"assembly_id"} } = $hash{"assembly_name"};

}

my $get_runs_by_organism_endpoint="http://plantain:3000/eg/getLibrariesByOrganism/"; # i get all the runs by organism to date that Robert has processed so far

my %robert_plants_done;
my %runs; # it stores all distinct run ids
my %current_studies; # it stores all distinct study ids
my %studyId_assemblyName; # stores key :study id and value: ensembl assembly name,ie for oryza_sativa it would be IRGSP-1.0
my %robert_plant_study;
my %studyId_lastProcessedDates;
my %study_Id_runId;

# a line of this call:  http://plantain:3000/eg/getLibrariesByOrganism/oryza_sativa
#[{"STUDY_ID":"DRP000315","SAMPLE_ID":"SAMD00009891","RUN_ID":"DRR000756","ORGANISM":"oryza_sativa_japonica_group","STATUS":"Complete","ASSEMBLY_USED":"IRGSP-1.0","ENA_LAST_UPDATED":"Fri Jun 19 2015 17:39:45",
#"LAST_PROCESSED_DATE":"Sat Sep 05 2015 22:40:36","FTP_LOCATION":"ftp://ftp.ebi.ac.uk/pub/databases/arrayexpress/data/atlas/rnaseq/DRR000/DRR000756/DRR000756.cram"},

foreach my $ens_plant (keys %ens_plant_names) { # i loop through the ensembl plant names to get from Robert all the done studies/runs

  my $array_express_url = $get_runs_by_organism_endpoint . $ens_plant;

  my @get_runs_by_organism_response = @{getJsonResponse($array_express_url)};  

  foreach my $hash_ref (@get_runs_by_organism_response){

    my %hash = %{$hash_ref};

    next unless($hash{"STATUS"} eq "Complete"); 

    $robert_plants_done{ $hash{"ORGANISM"} }++; 
    $robert_plant_study {$hash{"ORGANISM"} }  {$hash{"STUDY_ID"}} = 1;
    $runs {$hash{"RUN_ID"}} = 1;
    $current_studies {$hash {"STUDY_ID"}} = 1 ;
        
    $studyId_assemblyName { $hash {"STUDY_ID"} } { $hash {"ASSEMBLY_USED"} } = 1; # i can have more than one assembly for each study

    $studyId_lastProcessedDates { $hash {"STUDY_ID"} } { $hash {"LAST_PROCESSED_DATE"} } =1 ;  # i get different last processed dates from different the runs of the study
    $study_Id_runId { $hash{"STUDY_ID"} } { $hash{"RUN_ID"} } = 1;
        
  }
}

my %studyId_date;
 
foreach my $study_id (keys %studyId_lastProcessedDates ){  
#each study has more than 1 processed date, as there are usually multiple runs in each study with different processed date each. I want to get the most current date

  my $max_date=0;
  foreach my $date (keys %{$studyId_lastProcessedDates {$study_id}}){

    my $unix_time = UnixDate( ParseDate($date), "%s" );

    if($unix_time > $max_date){
      $max_date = $unix_time ;
    }
  }

  $studyId_date {$study_id} = $max_date ;

}

my $line_counter = 0;
my %obsolete_studies;
my %common_studies;
my %common_updated_studies;
my %new_studies;
my @skipped_studies_due_to_registry_issues;

if($from_scratch) {

  print "\n ******** starting to make directories and files for the track hubs in the ftp server: $http_url\n\n";

  foreach my $study_id (keys %studyId_assemblyName){ 

    $line_counter ++;
    print "$line_counter.\tcreating track hub for study $study_id\t"; 
    my $script_output ;
    if ( $use_ena_warehouse_meta) {
      $script_output = `perl create_track_hub_using_ena_warehouse_metadata.pl -study_id $study_id -local_ftp_dir_path $ftp_local_path -http_url $http_url` ; # here I create for every study a track hub *********************
    }else {
      $script_output = `perl create_track_hub.pl -study_id $study_id -local_ftp_dir_path $ftp_local_path -http_url $http_url` ; # here I create for every study a track hub *********************
    }
    print $script_output;
    if($script_output !~ /..Done/){  # if for some reason the track hub didn't manage to be made in the server, it shouldn't be registered in the Registry, for example Robert gives me a study id as completed that is not yet in ENA
      print STDERR "Track hub of $study_id could not be made in the server - I have deleted the folder $study_id\n\n" ;
      `rm -r $ftp_local_path/$study_id`;
      $line_counter --;
      push (@study_ids_not_yet_in_ena, $study_id);

      if($? !=0){ # if rm is successful, it returns 0 
        die "I cannot rm dir $ftp_local_path/$study_id in script: ".__FILE__." line: ".__LINE__."\n";
      }
    }else{  # if the study is successfully created in the ftp server, I go ahead and register it

      my $output = register_study($study_id);

      if($output !~ /is Registered/){# if something went wrong with the registration, i will not make a track hub out of this study
        `rm -r $ftp_local_path/$study_id`;
        if($? !=0){ # if rm is successful, it returns 0 
          die "I cannot rm dir $ftp_local_path/$study_id in script: ".__FILE__." line: ".__LINE__."\n";
        }
        $line_counter --;
        print "		..Something went wrong with the Registration process -- this study will be skipped..\n";
        push(@skipped_studies_due_to_registry_issues,$study_id);
      }
      print $output;
      
    }
  }

  my $date_string2 = localtime();
  print " \n Finished creating the files,directories of the track hubs on the server on:\n";
  print "Local date,time: $date_string2\n";

  print "\n***********************************\n\n";

}else{ # incremental update  -- here i decide which studies are new / to-be updated / obsolete

  foreach my $study_id (keys %current_studies){ # current studies from Robert that are completed

    if(!$studies_last_run_of_pipeline{$study_id}){ # if study is not in the server, then it's a new study I have to make a track hub for
      $new_studies{$study_id} = 1;
    }else{
      $common_studies {$study_id} = 1;
    }

  }
   
  foreach my $study_id (keys %studies_last_run_of_pipeline){ # studies in the ftp server from last time I ran the pipeline

    if(!$current_studies{$study_id}){ # if study is in the server but not in the current list of Robert it means that this study is removed from ENA
      $obsolete_studies{$study_id} = 1;
    }
  }

  if(scalar (keys %obsolete_studies) >0){

    print "\n**********starting to delete obsolete track hubs from the trackHub Registry and the server:\n\n";

  }else{
    print "\nThere are not any obsolete track hubs to be removed since the last time the pipeline was run.\n\n";
  }

  foreach my $study_to_remove (keys %obsolete_studies){

    `rm -r $ftp_local_path/$study_to_remove` ;  # removal from the server

    if($? ==0){ # if rm is successful, i get 0
 
      print "$study_to_remove successfully deleted from the server\n";

    }else{
      print "$study_to_remove could not be deleted from the server\n";
    }
    `perl delete_registered_trackhubs.pl -study_id $study_to_remove  -username $registry_user_name  -password $registry_pwd -study_id  $study_to_remove`; #removal from the registry
 
  }

  foreach my $common_study (keys %common_studies){  # from the common studies, I want to see which ones were updated from Robert , after I last ran the pipeline. I will update only those ones.
 
    my $roberts_last_processed_unix_time = $studyId_date {$common_study};

    my $study_created_date_unix_time = eval { get_Registry_hub_last_update($common_study) };

    if ($@) { # if the get_Registry_hub_last_update method fails to return the date of the track hub , then i re-do it anyways to be on the safe side

      my @table;
      $table[0]= "registry_no_response";
      $common_updated_studies {$common_study} = \@table;
      print "Couldn't get hub update: $@\ngoing to update hub anyway\n"; 

    }elsif($study_created_date_unix_time) {

      # I want to check also if the runs of the common study are the same in the Registry and in Array Express:

      my %runs_in_Registry = %{give_all_runs_of_study_from_Registry($common_study)};
      my %runs_in_Array_Express = %{$study_Id_runId {$common_study}} ;  #    $study_Id_runId { $hash{"STUDY_ID"} } { $hash{"RUN_ID"} } = 1;
      my @runs_numbers_holder;
      $runs_numbers_holder[1]= scalar (keys %runs_in_Registry); # in cell 1 of this table it's stored the number of runs of the common study in the Registry
      $runs_numbers_holder[2]= scalar (keys %runs_in_Array_Express);  # in cell 2 of this table it's stored the number of runs of the common study in current Array Express API call

      my $are_runs_the_same = hash_keys_are_equal(\%runs_in_Registry,\%runs_in_Array_Express); # returns 0 id they are not equal, 1 if they are
        
      if( $study_created_date_unix_time < $roberts_last_processed_unix_time or $are_runs_the_same ==0) { # if the study has now different runs it needs to be updated

        if( $study_created_date_unix_time < $roberts_last_processed_unix_time and $are_runs_the_same ==1){
          $runs_numbers_holder[0] = "diff_time_only";
          $common_updated_studies {$common_study}=\@runs_numbers_holder;
        }
        if ( $study_created_date_unix_time >= $roberts_last_processed_unix_time and $are_runs_the_same ==0) { # different number of runs
          $runs_numbers_holder[0] = "diff_number_runs_only";
          $common_updated_studies {$common_study}=\@runs_numbers_holder;
        }
        if( $study_created_date_unix_time < $roberts_last_processed_unix_time and $are_runs_the_same ==0){
          $runs_numbers_holder[0] = "diff_number_runs_diff_time";
          $common_updated_studies {$common_study}=\@runs_numbers_holder;
        }
      }
    } else {
      die "I have to really die here since I don't know what happened in script ".__FILE__." line ".__LINE__."\n";
    } 
  }
   
} # end of the incremental update   decision of  which studies are new / to-be updated / obsolete

my %studies_to_be_re_made = (%common_updated_studies , %new_studies);

if(scalar keys %studies_to_be_re_made !=0){

  print "\n ******** starting to make directories and files for the track hubs in the ftp server that are new/updated: $http_url\n\n";
  $line_counter = 0;

  foreach my $study_id (keys %studies_to_be_re_made){ 

    $line_counter ++;
    print "$line_counter.\tcreating track hub for study $study_id";
    if ($new_studies{$study_id}){
      print " (new study)";
    }
    if (ref($studies_to_be_re_made{$study_id}) eq 'ARRAY' ){  # if the hash value is a ref to an array
      
      my @table_content = @{$studies_to_be_re_made{$study_id}};

      if($table_content[0] eq "registry_no_response"){

        print " (Registry unable to give last update date - had to re-do trackhub)";

      }elsif($table_content[0] eq "diff_number_runs_only") {

        print " (Updated) Different number/ids of runs: Last Registered number of runs: ".$table_content[1].", Runs in Array Express currently: ".$table_content[2];

      }elsif($table_content[0] eq "diff_time_only") {

        my $date_registry_last = localtime(get_Registry_hub_last_update($study_id))->strftime('%F %T');
        my $date_cram_created = localtime($studyId_date{$study_id})->strftime('%F %T');

        print " (Updated) Last registered date: ".$date_registry_last  . ", Max last processed date of CRAMS from study: ".$date_cram_created;

      }elsif($table_content[0] eq "diff_number_runs_diff_time"){

        my $date_registry_last = localtime(get_Registry_hub_last_update($study_id))->strftime('%F %T');
        my $date_cram_created = localtime($studyId_date{$study_id})->strftime('%F %T');

        print " (Updated) Last registered date: ".$date_registry_last  . ", Max last processed date of CRAMS from study: ".$date_cram_created . " and also different number/ids of runs: "." Last Registered number of runs: ".$table_content[1].", Runs in Array Express currently: ".$table_content[2];
      }
    }
    print "\t";

#     my $ls_output = `ls $ftp_local_path`  ;
# 
#     if($? !=0){ # if ls is successful, it returns 0
#  
#       die "I cannot ls $ftp_local_path in script: ".__FILE__." line: ".__LINE__."\n";
# 
#     }
# 
#     my $dir_name_old = $study_id ."_old";
# 
#     if($ls_output=~/$study_id/){ # if it's not a new study it will be in the ftp server, so I have to check
# 
#       `mv $ftp_local_path/$study_id $ftp_local_path/$dir_name_old`; # first rename it in the server for security- in case smt goes wrong , I don't want to lose it
# 
#       if($? !=0){ # if mv is successful, it returns 0
#  
#         die "I cannot mv dir $ftp_local_path/$study_id to $study_id $ftp_local_path/$dir_name in script: ".__FILE__." line: ".__LINE__."\n";
# 
#       }
#     }          

    my $dir_name_old = $study_id ."_old";
    if(!$new_studies{$study_id})   { # if it's a common study for update:

      `mv $ftp_local_path/$study_id $ftp_local_path/$dir_name_old`; # first rename it in the server for security- in case smt goes wrong , I don't want to lose it

      if($? !=0){ # if mv is successful, it returns 0
 
        die "I cannot mv dir $ftp_local_path/$study_id to $study_id $ftp_local_path/$dir_name_old in script: ".__FILE__." line: ".__LINE__."\n";

      }
    }
    my $output_script;
    if ($use_ena_warehouse_meta) {

      $output_script = `perl create_track_hub_using_ena_warehouse_metadata.pl -study_id $study_id -local_ftp_dir_path $ftp_local_path -http_url $http_url` ; # here I create for every study a track hub *********************

    }else{ 
      $output_script = `perl create_track_hub.pl -study_id $study_id -local_ftp_dir_path $ftp_local_path -http_url $http_url` ; # here I create for every study a track hub *********************
    }
    print $output_script;

    if($output_script !~ /..Done/){  # if for some reason the track hub didn't manage to be made in the server, it shouldn't be registered in the Registry, for example Robert gives me a study id as completed that is not yet in ENA

      my $ls_output2 = `ls $ftp_local_path`  ;

      if($? !=0){ # if ls is successful, it returns 0
 
        die "I cannot ls $ftp_local_path in script: ".__FILE__." line: ".__LINE__."\n";

      }

      `rm -r $ftp_local_path/$study_id`;
      if($? !=0){ # if rm is successful, it returns 0
 
        die "I cannot rm $ftp_local_path/$study_id in script: ".__FILE__." line: ".__LINE__."\n";

      }

      if($ls_output2 =~/$dir_name_old/){

        `mv $ftp_local_path/dir_name_old $ftp_local_path/$study_id`; # if smt goes wrong when trying to update a track hub , I put it back to its previous state        
        print STDERR "Track hub of $study_id could not be updated in the server - I have left it to its previous state $study_id\n\n" ;

      } 
      if($new_studies{$study_id}){  # if it's a new study that didn't go well
         print STDERR "Track hub of $study_id could not be made in the server - I have deleted the folder $study_id\n\n" ;
      }
      
      $line_counter --;
      push (@study_ids_not_yet_in_ena, $study_id);

      next; # i go to the next study, since I don't want to register the study that failed to be created in the ftp server

    }else{  # if things went well, I remove the back up file

      `rm -r $ftp_local_path/$dir_name_old`;
      if($? !=0){ # if rm is successful, it returns 0
 
        die "I cannot rm $ftp_local_path/$dir_name_old in script: ".__FILE__." line: ".__LINE__."\n";

      }

    }

  ##### Registration part

    my $output = register_study($study_id);

    if($output !~ /is Registered/){# if something went wrong with the registration, i will not make a track hub out of this study if it's a new study and I will leave the updated study to its previous status
      if ($new_studies{$study_id}){
        `rm -r $ftp_local_path/$study_id`;
        if($? !=0){ # if rm is successful, it returns 0 
          die "I cannot rm dir $ftp_local_path/$study_id in script: ".__FILE__." line: ".__LINE__."\n";
        }
      }else{ # if there is a common to-be updated study, and smt went wrong with the Registry, I put it back in the server in its previous status
        `rm $ftp_local_path/$dir_name_old` ;
        if($? !=0){ # if rm is successful, it returns 0
 
          die "I cannot rm $ftp_local_path/$dir_name_old in script: ".__FILE__." line: ".__LINE__."\n";

        }
        `mv $ftp_local_path/dir_name_old $ftp_local_path/$study_id`; # if smt goes wrong when trying to update a track hub , I put it back to its previous state        
        print STDERR "Track hub of $study_id could not be updated in the server - I have left it to its previous state $study_id\n\n" ;
      }

      $line_counter --;
      print "	..Something went wrong with the Registration process -- this study will be skipped..\n";
      push(@skipped_studies_due_to_registry_issues,$study_id);
    }
    print $output;

  #####
  }

my $date_string2 = localtime();
print " \n Finished creating the files,directories of the track hubs on the server on:\n";
print "Local date,time: $date_string2\n";
print "\n***********************************\n\n";

}else{
  if(!$from_scratch){
    print "\nThere are not any updated or new tracks to be made since the last time the pipeline was run.\n";
  }
} 


my $dt = DateTime->today;

my $date_wrong_order = $dt->date;  # it is in format 2015-10-01
# i want 01-10-2015

my @words = split(/-/, $date_wrong_order);
my $current_date = $words[2] . "-". $words[1]. "-". $words[0];  # ie 01-10-2015 (1st October)
   
print "\n####################################################################################\n";
print "\nArray Express REST calls give the following stats:\n";
print "\nThere are " . scalar (keys %runs) ." plant runs completed to date ( $current_date )\n";
print "\nThere are " . scalar (keys %current_studies) ." plant studies completed to date ( $current_date )\n";

print "\n****** Plants done to date: ******\n\n";

my $counter_ens_plants = 0 ; 
my $index = 0;

foreach my $plant (keys %robert_plants_done){

  if($ens_plant_names {$plant}){
    $counter_ens_plants++;
    print " * " ;
  }
  $index++;
  print $index.". ".$plant." =>\t". $robert_plants_done{$plant}." runs / ". scalar ( keys ( %{$robert_plant_study{$plant}} ) )." studies\n";

}
print "\n";


print "In total there are " .$counter_ens_plants . " Ensembl plants done to date.\n\n";
print "####################################################################################\n\n";

my $date_string_end = localtime();
print " Finished running the pipeline on:\n";
print "Local date,time: $date_string_end\n";



my $total_disc_space_of_track_hubs = `du -sh $ftp_local_path`;
  
print "\nTotal disc space occupied in $ftp_local_path is:\n $total_disc_space_of_track_hubs\n";

print "There are in total ". give_number_of_dirs_in_ftp(). " files in the ftp server\n\n";

my $all_track_hubs_in_registry_after_update = give_all_Registered_track_hubs();
my %distinct_runs;

foreach my $hub_name (keys %{$all_track_hubs_in_registry_after_update}){
  
  map { $distinct_runs{$_}++ } keys %{give_all_runs_of_study_from_Registry($hub_name)};
}

print "There in total ". scalar (keys %{$all_track_hubs_in_registry_after_update}). " track hubs with total ".scalar (keys %distinct_runs)." runs registered in the Track Hub Registry\n\n";


if (scalar @study_ids_not_yet_in_ena > 0){
  print "These studies were ready by Array Express but not yet in ENA , so no trak hubs were able to be created out of those, since the metadata needed for the track hubs are taken from ENA:\n";
  my $count_unready_studies=0;
  foreach my $study_id (@study_ids_not_yet_in_ena){
    $count_unready_studies++;
    my %runs_hash = %{$study_Id_runId{$study_id}};
    print $count_unready_studies.".".$study_id." (".scalar (keys %runs_hash)." runs)\n";
  }
}


if (scalar @skipped_studies_due_to_registry_issues > 0){
  print "These studies were not able to be registered in the Track Hub Registry , hence skipped (removed from the ftp server too):\n";
  my $count_skipped_studies=0;
  foreach my $study_id (@skipped_studies_due_to_registry_issues){
    $count_skipped_studies++;
    my %runs_hash = %{$study_Id_runId{$study_id}};
    print $count_skipped_studies.".".$study_id." (".scalar (keys %runs_hash)." runs)\n";
  }
}


### methods used 


sub getJsonResponse { # it returns the json response given the url-endpoint as param, it returns an array reference that contains hash references . If response not successful it returns 0

  my $url = shift; 

  my $response_http = eval {$http->get($url)} ;

  if ($@) {
    print STDERR "\nCould not get response from REST call of url $url\n";
    return 0;
  }

  my $response = $http->get($url); 


  if($response->{success} ==1) { # if the response is successful then I get 1

    my $content=$response->{content};      # it prints whatever is the content of the URL, ie the json response
    my $json = decode_json($content);      # it returns an array reference 

    return $json;

  }else{

    my ($status, $reason) = ($response->{status}, $response->{reason}); 
    print STDERR "ERROR in: ".__FILE__." line: ".__LINE__ ." Failed for $url! Status code: ${status}. Reason: ${reason}\n";  # if response is successful I get status "200", reason "OK"
    return 0;
  }
}


sub registry_login {

  my ($server, $user, $pass) = @_;
  defined $server and defined $user and defined $pass
    or die "Some required parameters are missing when trying to login in the Track Hub Registry\n";
  
  my $ua = LWP::UserAgent->new;
  my $endpoint = '/api/login';
  my $url = $server.$endpoint; 

  my $request = GET($url);
  $request->headers->authorization_basic($user, $pass);

  my $response = $ua->request($request);
  my $auth_token;

  if ($response->is_success) {
    $auth_token = from_json($response->content)->{auth_token};
  } else {
    die "Unable to login to Registry, reason: " .$response->code ." , ". $response->content."\n";
  }
  
  defined $auth_token or die "Undefined authentication token when trying to login in the Track Hub Registry\n";
  return $auth_token;

}

sub registry_logout {

  my ($server, $user, $auth_token) = @_;
  defined $server and defined $user and defined $auth_token
    or die "Some required parameters are missing when trying to log out from the Track Hub Registry\n";
  
  my $ua = LWP::UserAgent->new;
  my $request = GET("$server/api/logout");
  $request->headers->header(user => $user);
  $request->headers->header(auth_token => $auth_token);
  my $response = $ua->request($request);

  if (!$response->is_success) {
    die "Couldn't log out from the registry\n";
  } 
  return;
}


sub give_all_Registered_track_hubs{

  my %track_hub_names;

  my $auth_token = eval { registry_login($registry_server, $registry_user_name, $registry_pwd) };
  if ($@) {
    print "Couldn't login, skipping getting all registered trackhubs: $@\n";
    return;
  }

  my $ua = LWP::UserAgent->new;
  my $request = GET("$registry_server/api/trackhub");
  $request->headers->header(user => $registry_user_name);
  $request->headers->header(auth_token => $auth_token);
  my $response = $ua->request($request);

  my $response_code= $response->code;

  if($response_code == 200) {
    my $trackhubs = from_json($response->content);
    map { $track_hub_names{$_->{name}} = 1 } @{$trackhubs}; # it is same as : $track_hub_names{$trackhubs->[$i]{name}}=1; 

  }else{

    print "Couldn't get Registered track hubs with the first attempt when calling method give_all_Registered_track_hubs in script ".__FILE__."\n";
    print "Got error ".$response->code ." , ". $response->content."\n";
    my $flag_success=0;

    for(my $i=1; $i<=10; $i++) {

      print $i .".Retrying attempt: Retrying after 5s...\n";
      sleep 5;
      $response = $ua->request($request);
      if($response->is_success){
        $flag_success =1 ;
        my $trackhubs = from_json($response->content);
        map { $track_hub_names{$_->{name}} = 1 } @{$trackhubs};
        last;
      }
    }

    die "Couldn't get list of track hubs in the Registry when calling method give_all_Registered_track_hubs in script: ".__FILE__." line ".__LINE__."\n"
    unless $flag_success ==1;
  }

  #registry_logout($registry_server, $registry_user_name, $auth_token);

  return \%track_hub_names;

}


sub get_Registry_hub_last_update {

  my $name = shift;  # track hub name, ie study_id

  my $auth_token = eval { registry_login($registry_server, $registry_user_name, $registry_pwd) };
  if ($@) {
    print "Couldn't login, skipping getting all registered trackhubs\n";
    return;
  }
  my $ua = LWP::UserAgent->new;  
  my $request = GET("$registry_server/api/trackhub/$name");
  $request->headers->header(user       => $registry_user_name);
  $request->headers->header(auth_token => $auth_token);
  my $response = $ua->request($request);
  my $hub;

  if ($response->is_success) {
    $hub = from_json($response->content);
  } else {  

    print "Couldn't get Registered track hubs with the first attempt when calling method get_Registry_hub_last_update in script ".__FILE__."\n";
    my $flag_success=0;

    for(my $i=1; $i<=10; $i++) {

      print $i .".Retrying attempt: Retrying after 5s...\n";
      sleep 5;
      $response = $ua->request($request);
      if($response->is_success){
        $hub = from_json($response->content);
        $flag_success =1 ;
        last;
      }
    }

    die "Couldn't get list of track hubs in the Registry when calling method get_Registry_hub_last_update in script: ".__FILE__." line ".__LINE__."\n"
    unless $flag_success==1;
  }

  die "Couldn't find hub $name in the Registry to get the last update date when calling method get_Registry_hub_last_update in script: ".__FILE__." line ".__LINE__."\n" 
  unless $hub;

  my $last_update = -1;

  foreach my $trackdb (@{$hub->{trackdbs}}) {

    $request = GET($trackdb->{uri});
    $request->headers->header(user       => $registry_user_name);
    $request->headers->header(auth_token => $auth_token);
    $response = $ua->request($request);
    my $doc;
    if ($response->is_success) {
      $doc = from_json($response->content);
    } else {  
      die "Couldn't get trackdb at", $trackdb->{uri}." from study $name in the Registry when trying to get the last update date \n";
    }

    if (exists $doc->{updated}) {
      $last_update = $doc->{updated}
      if $last_update < $doc->{updated};
    } else {
      exists $doc->{created} or die "Trackdb does not have creation date in the Registry when trying to get the last update date of study $name\n";
      $last_update = $doc->{created}
      if $last_update < $doc->{created};
    }
  }

  die "Couldn't get date as expected: $last_update\n" unless $last_update =~ /^[1-9]\d+?$/;

  #registry_logout($registry_server, $registry_user_name, $auth_token);

  return $last_update;
}

sub give_all_runs_of_study_from_Registry {

  my $name = shift;  # track hub name, ie study_id
  

  my $auth_token = eval { registry_login($registry_server, $registry_user_name, $registry_pwd) };
  if ($@) {
    print "Couldn't login, skipping getting all registered trackhubs\n";
    return;
  }
 
  my $ua = LWP::UserAgent->new;
  my $request = GET("$registry_server/api/trackhub/$name");
  $request->headers->header(user       => $registry_user_name);
  $request->headers->header(auth_token => $auth_token);
  my $response = $ua->request($request);
  my $hub;

  if ($response->is_success) {

    $hub = from_json($response->content);

  } else {  

    print "Couldn't get Registered track hub $name with the first attempt when calling method give_all_runs_of_study_from_Registry in script ".__FILE__." reason " .$response->code ." , ". $response->content."\n";
    my $flag_success=0;

    for(my $i=1; $i<=10; $i++) {

      print $i .".Retrying attempt: Retrying after 5s...\n";
      sleep 5;
      $response = $ua->request($request);
      if($response->is_success){
        $hub = from_json($response->content);
        $flag_success =1 ;
        last;
      }
    }

    die "Couldn't get the track hub $name in the Registry when calling method give_all_runs_of_study_from_Registry in script: ".__FILE__." line ".__LINE__."\n"
    unless $flag_success==1;
  }

  die "Couldn't find hub $name in the Registry to get its runs when calling method give_all_runs_of_study_from_Registry in script: ".__FILE__." line ".__LINE__."\n" 
  unless $hub;

  my %runs ;

  foreach my $trackdb (@{$hub->{trackdbs}}) {

    $request = GET($trackdb->{uri});
    $request->headers->header(user       => $registry_user_name);
    $request->headers->header(auth_token => $auth_token);

    # my $request = registry_get_request();
    $response = $ua->request($request);
    my $doc;

    if ($response->is_success) {

      $doc = from_json($response->content);


      foreach my $sample (keys %{$doc->{configuration}}) {
	map { $runs{$_}++ } keys %{$doc->{configuration}{$sample}{members}}; 
      }
    } else {  
      die "Couldn't get trackdb at ", $trackdb->{uri} , " from study $name in the Registry when trying to get all its runs, reason: " .$response->code ." , ". $response->content."\n";
    }
  }

  #registry_logout($registry_server, $registry_user_name, $auth_token);

  return \%runs;

}

sub registry_get_request {
  my ($server, $endpoint, $user, $token) = @_;

  my $request = GET("$server$endpoint");
  $request->headers->header(user       => $user);
  $request->headers->header(auth_token => $token);
  
  return $request;
}

sub give_number_of_dirs_in_ftp {

  my $ftp_location = $ftp_local_path;

  my @files = `ls $ftp_local_path` ;
  
  return  scalar @files;
}


sub getRightAssemblyName { # this method returns the right assembly name in the cases where Robert takes the assembly accession instead of the assembly name due to our bug

  my $assembly_string = shift;
  my $assembly_name;


  if (!$assName_assAccession{$assembly_string}){

    if(!$assAccession_assName{$assembly_string}) {  
      # solanum_tuberosum has a wrong assembly.default it's neither the assembly.name nor the assembly.accession BUT : "assembly_name":"SolTub_3.0" and "assembly_id":"GCA_000226075.1"

      $assembly_name = $assembly_string;
 
    }else{
      $assembly_name = $assAccession_assName{$assembly_string};
    }
  }else{
    $assembly_name = $assembly_string;
  }

  if($assembly_string eq "3.0"){ # this is an exception for solanum_tuberosum

    $assembly_name = "SolTub_3.0";
  }
  return $assembly_name;

}

sub hash_keys_are_equal{
   
  my ($hash1, $hash2) = @_;
  my $areEqual=1;

  if(scalar(keys %{$hash1}) == scalar (keys %{$hash2})){

    foreach my $key1(keys %{$hash1}) {
      if(!$hash2->{$key1}) {

        $areEqual=0;
      }
    }
  }else{
    $areEqual = 0;
  }

  return $areEqual;
}


sub register_study {

  my $study_id = shift;

  my $hub_txt_url = $http_url . "/" . $study_id . "/hub.txt" ;
           
  my @assembly_names_with_accessions;
      
  foreach my $assembly_name ( keys % {$studyId_assemblyName{$study_id}}) {   # from Robert's data , get runs by organism REST call                           
         
    $assembly_name = getRightAssemblyName($assembly_name); # as Robert gets the assembly.default that due to our bug could be the assembly.accession rather than the assembly.name

    if(!$assName_assAccession{$assembly_name}){ # from ensemblgenomes data

      print STDERR "ERROR: study $study_id will not be Registered as there is no assembly name \'$assembly_name\' (Robert's call) of study $study_id in my hash from ensemblgenomes REST call: $ens_genomes_plants_rest_call \n\n";
      next;  # this is for potato (solanum_tuberosum that has an invalid assembly.default name)
    }
    push ( @assembly_names_with_accessions, $assembly_name) ; # this array has only the assembly names that have assembly accessions

  }

  my @array_string_pairs;

  foreach my $assembly_name ( @assembly_names_with_accessions ){

    my $string =  $assembly_name.",".$assName_assAccession{$assembly_name} ;
    push (@array_string_pairs , $string);

  }

  my $assemblyNames_assemblyAccesions_string;

  if (scalar @array_string_pairs >=1 ){

    $assemblyNames_assemblyAccesions_string=$array_string_pairs[0];

  } else{
          
    $assemblyNames_assemblyAccesions_string="empty";
  }

  if (scalar @array_string_pairs > 1){

    $assemblyNames_assemblyAccesions_string=$array_string_pairs[0].",";

    for(my $index=1; $index< scalar @array_string_pairs; $index++){

      $assemblyNames_assemblyAccesions_string=$assemblyNames_assemblyAccesions_string.$array_string_pairs[$index];

      if ($index < scalar @array_string_pairs -1){

        $assemblyNames_assemblyAccesions_string = $assemblyNames_assemblyAccesions_string .",";
      }
               
    }
  }
 
  my $output = `perl register_track_hub.pl -username $registry_user_name -password $registry_pwd -hub_txt_file_location $hub_txt_url -assembly_name_accession_pairs $assemblyNames_assemblyAccesions_string` ;  # here I register every track hub in the Registry*********************
  return $output;
}
