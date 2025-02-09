import glob
import os
import subprocess
import re
import yaml
import sys
import copy

### Functions ##################################################################

def get_control(sample):
    """
    Return control sample name for a given ChIP-seq sample
    Return False if given ChIP-seq sample has no control
    """
    if sample in chip_samples_w_ctrl:
        return chip_dict[sample]['control']
    else:
        return False

def get_control_name(sample):
    """
    Return control sample alias for a given ChIP-seq sample
    Return False if given ChIP-seq sample has no control
    """
    if sample in chip_samples_w_ctrl:
        if 'control' in chip_dict[sample] and chip_dict[sample]['control'] != None:
            return chip_dict[sample]['control']
        else:
            return False
    else:
        return False

def is_broad(sample):
    """
    Return True if given ChIP-seq sample is annotated as sample with
    broad enrichment, else return False
    """
    if sample in chip_dict:
        return chip_dict[sample]['broad']
    else:
        return False


def is_chip(sample):
    """
    Return True if a given sample is a ChIP-seq sample
    Else return False
    """
    return (sample in chip_samples)


### Variable defaults ##########################################################
### Initialization #############################################################

# TODO: catch exception if ChIP-seq samples are not unique
# read ChIP-seq dictionary from config.yaml:
# { ChIP1: { control: Input1, broad: True }, ChIP2: { control: Input2, broad: false }
#config["chip_dict"] = {}

if not os.path.isfile(samples_config):
    print("ERROR: Cannot find samples file ("+samples_config+")")
    exit(1)

if sampleSheet:
    cf.check_sample_info_header(sampleSheet)
    if not cf.check_replicates(sampleSheet):
        print("\nWarning! CSAW cannot be invoked without replicates!\n")
        sys.exit()

chip_dict = {}
with open(samples_config, "r") as f:
    chip_dict_tmp = yaml.load(f, Loader=yaml.FullLoader)
    if "chip_dict" in chip_dict_tmp and chip_dict_tmp["chip_dict"] :
        chip_dict = chip_dict_tmp["chip_dict"]
    else:
        print("\n  Error! Sample config has empty or no 'chip_dict' entry! ("+config["samples_config"]+") !!!\n\n")
        exit(1)
    del chip_dict_tmp

chip_dict_ori = copy.deepcopy(chip_dict)

##If it is for the allele specific, we need to add allele_specific/ before sample name 
if any('.genome' in y for y in list(chip_dict.keys())) != 0:
    for k in chip_dict.keys():
        chip_dict[k]['control'] = 'allele_specific/' + chip_dict[k]['control']
    for k in chip_dict.fromkeys(chip_dict):
        new_key = 'allele_specific/' + k
        chip_dict[new_key] = chip_dict.pop(k)


cf.write_configfile(os.path.join("chip_samples.yaml"), chip_dict)

# create unique sets of control samples, ChIP samples with and without control
control_samples = set()
chip_samples_w_ctrl = set()
chip_samples_wo_ctrl = set()
for chip_sample, value in chip_dict.items():
    # set control to False if not specified or set to False
    if 'control' not in chip_dict[chip_sample] or not value['control']:
        chip_dict[chip_sample]['control'] = False
        chip_samples_wo_ctrl.add(chip_sample)
    else:
        control_samples.add(value['control'])
        chip_samples_w_ctrl.add(chip_sample)
    # set broad to False if not specified or set to False
    if 'broad' not in chip_dict[chip_sample] or not value['broad']:
        chip_dict[chip_sample]['broad'] = False

control_samples = list(sorted(control_samples))
# get a list of corresp control_names for chip samples
control_names = []
for chip_sample in chip_samples_w_ctrl:
    control_names.append(get_control_name(chip_sample))

chip_samples_w_ctrl = list(sorted(chip_samples_w_ctrl))
chip_samples_wo_ctrl = list(sorted(chip_samples_wo_ctrl))
chip_samples = sorted(chip_samples_w_ctrl + chip_samples_wo_ctrl)
all_samples = sorted(control_samples + chip_samples)

if not fromBAM and not useSpikeInForNorm:
    if pairedEnd:
        if not os.path.isfile(os.path.join(workingdir, "deepTools_qc/bamPEFragmentSize/fragmentSize.metric.tsv")):
            sys.exit('ERROR: {} is required but not present\n'.format(os.path.join(workingdir, "deepTools_qc/bamPEFragmentSize/fragmentSize.metric.tsv")))

    # consistency check whether all required files exist for all samples
    for sample in all_samples:
        req_files = [
            os.path.join(workingdir, "filtered_bam/"+sample+".filtered.bam"),
            os.path.join(workingdir, "filtered_bam/"+sample+".filtered.bam.bai")
            ]

        # check for all samples whether all required files exist
        #for file in req_files:
        #    if not os.path.isfile(file):
        #        print('ERROR: Required file "{}" for sample "{}" specified in '
        #              'configuration file is NOT available.'.format(file, sample))
        #        exit(1)

        
else:
    bamFiles = sorted(glob.glob(os.path.join(str(fromBAM or ''), '*' + bamExt)))
    bamSamples = cf.get_sample_names_bam(bamFiles, bamExt)
    
    bamDict = dict.fromkeys(bamSamples)
    
    for sample in all_samples:
        if sample not in bamDict:
            sys.exit("No bam file found for chip sample {}!".format(sample))
    aligner = "EXTERNAL_BAM"
    indir = fromBAM
    downsample = None

samples = all_samples
if not samples:
    print("\n  Error! NO samples found in dir "+str(indir or '')+"!!!\n\n")
    exit(1)


##filter sample dictionary by the subset of samples listed in the 'name' column of the sample sheet
def filter_dict(sampleSheet,input_dict):
    f=open(sampleSheet,"r")
    nameCol = None
    nCols = None
    names_sub=[]
    for idx, line in enumerate(f):
        cols = line.strip().split("\t")
        if idx == 0:
            nameCol = cols.index("name")
            nCols = len(cols)
            continue
        elif idx == 1:
            if len(cols) - 1 == nCols:
                nameCol += 1
        if not len(line.strip()) == 0:
            names_sub.append(line.split('\t')[nameCol])      
    f.close()
    output_dict = dict((k,v) for k,v in input_dict.items() if k in names_sub)
    return(output_dict)

if sampleSheet:
    temp_dict = dict(zip([re.sub("allele_specific/", "", x) for x in chip_samples_w_ctrl], [re.sub("allele_specific/", "", x) for x in [ get_control_name(x) for x in chip_samples_w_ctrl ] ]))
    filtered_dict = filter_dict(sampleSheet,temp_dict) #
    if any('.genome' in y for y in list(filtered_dict.keys())):
        for k in filtered_dict.keys():
            filtered_dict[k] = 'allele_specific/' + filtered_dict[k]
        for k in filtered_dict.fromkeys(filtered_dict):
            new_key = 'allele_specific/' + k
            filtered_dict[new_key] = filtered_dict.pop(k)
    genrichDict = cf.sampleSheetGroups(sampleSheet)
    if len([y for y in list(genrichDict.values())[0] if '.genome' in y]) != 0:
        for k in genrichDict.keys():
            genrichDict[k] = [ 'allele_specific/' + x  for x in genrichDict[k] ]
#    print(filtered_dict)
#    print(genrichDict)
    reordered_dict = {k: filtered_dict[k] for k in [item for sublist in genrichDict.values() for item in sublist]}
    for k in reordered_dict.keys():
        reordered_dict[k] = re.sub("allele_specific/", "", reordered_dict[k])
else:
    genrichDict = {"all_samples": chip_samples}


#################### functions and checks for using a spiked-in genome for normalization ########################################
def check_if_spikein_genome(genome_index,spikeinExt):
    resl=[]
    if os.path.isfile(genome_index):
        with open(genome_index) as ifile:
            for line in ifile:
                resl.append(re.search(spikeinExt, line))
        if any(resl):
            print("\n Spikein genome detected - at least one spikeIn chromosome found with extention " + spikeinExt + " .\n\n")
            return True
        else:
            return False
    else:
        print("\n  Error! Genome index file "+ genome_index +" not found!!!\n\n")
        exit(1)

def get_host_and_spikein_chromosomes(genome_index,spikeinExt):
    hostl=[]
    spikeinl=[]
    with open(genome_index) as ifile:
        for line in ifile:
            entry = line.split('\t')[0] 
            if re.search(spikeinExt, entry):
                spikeinl.append(entry)
            else:
                hostl.append(entry)
    return([hostl,spikeinl])

if useSpikeInForNorm:
    part=['host','spikein']
    spikein_detected=check_if_spikein_genome(genome_index,spikeinExt)
    if spikein_detected:
        host_chr=get_host_and_spikein_chromosomes(genome_index,spikeinExt)[0]
        spikein_chr=get_host_and_spikein_chromosomes(genome_index,spikeinExt)[1]
    else:
        print("\n No spikein genome detected - no spikeIn chromosomes found with extention " + spikeinExt + " .\n\n")
        exit(1)
        
       
