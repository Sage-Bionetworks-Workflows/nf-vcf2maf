#!/usr/bin/env nextflow

nextflow.enable.dsl=2

params.input = "$HOME/data/example.csv"
params.reference_fasta = "/dev/shm/fasta/Homo_sapiens_assembly38.fasta"
params.vep_data = "/dev/shm/vep/"

params.maf_center = "Sage Bionetworks"
params.max_subpop_af = 0.0005
params.ncbi_build = "GRCh38"


process SYNAPSE_GET {

  container "sagebionetworks/synapsepythonclient:v2.6.0"

  secret "SYNAPSE_AUTH_TOKEN"

  input:
  tuple val(meta), val(synapse_id)

  output:
  tuple val(meta), path('*')

  script:
  """
  synapse get '${synapse_id}'
  """

}


// TODO: Look at other vcf2maf options (like the sample names)
process VCF2MAF {

  container "sagebionetworks/vcf2maf:107.1"

  input:                
  tuple val(meta), path(input_vcf)
  path reference_fasta
  path vep_data

  output:               
  tuple val(meta), path("*.maf")

  script:
  vep_path = "/root/miniconda3/envs/vep/bin"
  """
  vcf2maf.pl \
    --input-vcf '${input_vcf}' --output-maf ${input_vcf.baseName}.maf --ref-fasta '${reference_fasta}' \
    --vep-data '${vep_data}' --ncbi-build '${params.ncbi_build}' --max-subpop-af '${params.max_subpop_af}' \
    --vep-path '${vep_path}' --maf-center '${params.maf_center}'
  """

}


// TODO: Sanity check output
// TODO: Incorporate script inside container (or copy script to this repo)
process MERGE_MAFS {

  container "python:3.10.4"

  input:                
  tuple val(meta), path(input_mafs)

  output:
  tuple val(meta), path("*.merged.maf")

  script:
  script_url = "https://raw.githubusercontent.com/genome-nexus/annotation-tools/master/merge_mafs.py"
  """
  wget ${script_url}
  python3 merge_mafs.py \
    -o ${meta.study_id}-${meta.variant_class}-${meta.variant_caller}.merged.maf \
    -i ${input_mafs.join(',')}
  """

}


// TODO: Store Python script in a separate file
process FILTER_MAF {

  container "python:3.10.4"

  input:
  tuple val(meta), path(input_maf)

  output:
  tuple val(meta), path("*.passed.maf")

  script:
  """
  #!/usr/bin/env python3

  import csv

  with (
      open('${input_maf}', newline='') as infile, 
      open('${input_maf.baseName}.passed.maf', "w", newline='') as outfile
  ):
    reader = csv.DictReader(infile, delimiter='\t')
    writer = csv.DictWriter(outfile, reader.fieldnames, delimiter='\t')
    for row in reader:
      if row['FILTER'] == 'PASS':
        writer.writerow(row)
  """

}


process SYNAPSE_STORE {

  container "sagebionetworks/synapsepythonclient:v2.6.0"

  secret "SYNAPSE_AUTH_TOKEN"

  input:
  tuple path(input), val(parent_id)

  script:
  """
  synapse store --parentId '${parent_id}' '${input}'
  """

}


// TODO: Add comments
workflow SAMPLE_MAFS {

  take:
    sample_vcfs

  main:
    SYNAPSE_GET(sample_vcfs)

    VCF2MAF(SYNAPSE_GET.out, params.reference_fasta, params.vep_data)

    sample_mafs_ch = VCF2MAF.out
      .map { meta, maf -> [ maf, meta.sample_parent_id ] }

    SYNAPSE_STORE(sample_mafs_ch)
  
  emit:
    VCF2MAF.out

}


// TODO: Add comments
workflow MERGED_MAFS {

  take:
    sample_mafs

  main:
    merged_inputs_ch = sample_mafs
      .filter { meta, maf -> meta.is_releasable }
      .map {
          vcf_meta, maf ->
            def study_meta = [:]
            study_meta.merged_parent_id = vcf_meta.merged_parent_id
            study_meta.study_id         = vcf_meta.study_id
            study_meta.variant_class    = vcf_meta.variant_class
            study_meta.variant_caller   = vcf_meta.variant_caller
            [ study_meta, maf ] 
      }
      .groupTuple( by: 0 )
    
    MERGE_MAFS(merged_inputs_ch)

    FILTER_MAF(MERGE_MAFS.out)

    merged_mafs_ch = MERGE_MAFS.out
      .map { meta, maf -> [ maf, meta.merged_parent_id ] }

    filtered_mafs_ch = FILTER_MAF.out
      .map { meta, maf -> [ maf, meta.merged_parent_id ] }

    both_mafs_ch = merged_mafs_ch.mix(filtered_mafs_ch)

    SYNAPSE_STORE(both_mafs_ch)

}


workflow {

  input_vcfs_ch = Channel
    .fromPath ( params.input )
    .splitCsv ( header:true, sep:',' )
    .map { create_vcf_channel(it) }

  SAMPLE_MAFS(input_vcfs_ch)

  MERGED_MAFS(SAMPLE_MAFS.out)

}


// Function to get list of [ meta, vcf ]
def create_vcf_channel(LinkedHashMap row) {
  
  // Create metadata element
  def meta = [:]
  meta.sample_parent_id = row.sample_parent_id
  meta.merged_parent_id = row.merged_parent_id
  meta.study_id         = row.study_id
  meta.variant_class    = row.variant_class
  meta.variant_caller   = row.variant_caller
  meta.is_releasable    = row.is_releasable.toBoolean()

  // Combine with VCF file element
  def vcf_meta = [meta, row.synapse_id]

  return vcf_meta
}
