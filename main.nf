#!/usr/bin/env nextflow

nextflow.enable.dsl=2


process SYNAPSE_GET {

  tag "${meta.synapse_id}"

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


process EXTRACT_TAR_GZ {

  container "sagebionetworks/vcf2maf:107.2"

  input:
  path vep_tarball

  output:
  path "vep_data"

  script:
  """
  mkdir -p 'vep_data/'
  tar -zxf '${vep_tarball}' -C 'vep_data/'
  """

}


// TODO: Handle VCF genotype columns per variant caller
// TODO: Improve handling of vep_path
process VCF2MAF {

  tag "${meta.synapse_id}"

  container "sagebionetworks/vcf2maf:107.2"

  cpus 8
  memory '16.GB'

  afterScript "rm -f intermediate*"

  input:                
  tuple val(meta), path(input_vcf)
  tuple path(reference_fasta), path(reference_fasta_fai)
  path vep_data

  output:               
  tuple val(meta), path("*.maf")

  script:
  vep_path = "/root/miniconda3/envs/vep/bin"
  """
  if [[ ${input_vcf} == *.gz ]]; then
    zcat '${input_vcf}' | head -n 10000 > 'intermediate.vcf'
  else
    cat  '${input_vcf}' | head -n 10000 > 'intermediate.vcf'
  fi

  vcf2maf.pl \
    --input-vcf 'intermediate.vcf' --output-maf 'intermediate.maf.raw' \
    --ref-fasta '${reference_fasta}' --vep-data '${vep_data}/' \
    --ncbi-build '${params.ncbi_build}' --max-subpop-af '${params.max_subpop_af}' \
    --vep-path '${vep_path}' --maf-center '${params.maf_center}' \
    --tumor-id '${meta.biospecimen_id}' --vep-forks '${task.cpus}' \
    --species ${params.species}

  grep -v '^#' 'intermediate.maf.raw' > '${meta.biospecimen_id}-${meta.variant_class}-${meta.variant_caller}.maf'
  """

}


process FILTER_MAF {

  tag "${input_maf.name}"

  container "python:3.10.4"

  input:
  tuple val(meta), path(input_maf)

  output:
  tuple val(meta), path("*.passed.maf")

  script:
  """
  filter_maf.py ${input_maf} ${input_maf.baseName}.passed.maf
  """

}


// TODO: Sanity check output
process MERGE_MAFS {

  tag "${meta.study_id}-${meta.variant_class}-${meta.variant_caller}"

  container "python:3.10.4"

  input:                
  tuple val(meta), path(input_mafs)

  output:
  tuple val(meta), path("*.merged.maf")

  script:
  """
  merge_mafs.py \
    -o ${meta.study_id}-${meta.variant_class}-${meta.variant_caller}.merged.maf \
    -i ${input_mafs.join(',')}
  """
}


process SYNAPSE_STORE {

  tag "${parent_id}/${input.name}"

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
    reference_fasta_pair = [
      params.reference_fasta, params.reference_fasta_fai
    ]

    SYNAPSE_GET(sample_vcfs)

    EXTRACT_TAR_GZ(params.vep_tarball)

    VCF2MAF(SYNAPSE_GET.out, reference_fasta_pair, EXTRACT_TAR_GZ.out)

    sample_mafs_ch = VCF2MAF.out
      .map { meta, maf -> [ maf, meta.sample_parent_id ] }

    SYNAPSE_STORE(sample_mafs_ch)

    FILTER_MAF(VCF2MAF.out)
  
  emit:
    FILTER_MAF.out

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

    merged_mafs_ch = MERGE_MAFS.out
      .map { meta, maf -> [ maf, meta.merged_parent_id ] }

    SYNAPSE_STORE(merged_mafs_ch)

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
  meta.synapse_id       = row.synapse_id
  meta.biospecimen_id   = row.biospecimen_id
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
