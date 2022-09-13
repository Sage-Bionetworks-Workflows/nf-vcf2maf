#!/usr/bin/env nextflow

nextflow.enable.dsl=2

params.input_vcf = "$HOME/data/test-small*.vcf"
params.reference_fasta = "/dev/shm/fasta/Homo_sapiens_assembly38.fasta"
params.vep_data = "/dev/shm/vep/"

params.maf_center = "Sage Bionetworks"
params.max_subpop_af = 0.0005
params.ncbi_build = "GRCh38"


process VCF2MAF {

  container "sagebionetworks/vcf2maf:gnomad-genomes"

  input:                
  path input_vcf
  path reference_fasta
  path vep_data

  output:               
  path 'output.maf'

  script:
  vep_path = "/root/miniconda3/envs/vep/bin"
  """
  vcf2maf.pl \
    --input-vcf ${input_vcf} --output-maf output.maf --ref-fasta ${reference_fasta} \
    --vep-data ${vep_data} --ncbi-build ${params.ncbi_build} --max-subpop-af ${params.max_subpop_af} \
    --vep-path ${vep_path} --maf-center ${params.maf_center}
  """

}


workflow {
  input_vcf_ch = Channel.fromPath(params.input_vcf, checkIfExists: true)
  VCF2MAF(input_vcf_ch, params.reference_fasta, params.vep_data)
  VCF2MAF.out.view()
}
