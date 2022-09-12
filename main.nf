#!/usr/bin/env nextflow

nextflow.enable.dsl=2

params.input_vcf = "$HOME/data/test-small.vcf"
params.reference_fasta = "/dev/shm/fasta/Homo_sapiens_assembly38.fasta"
params.vep_data = "/dev/shm/vep/"

process VCF2MAF {

  container 'nfosi/vcf2maf:latest'

  input:                
  path input_vcf
  path reference_fasta
  path vep_data

  output:               
  path 'output.maf'

  script:
  """
  perl /nf-osi-vcf2maf-*/vcf2maf.pl \
    --input-vcf ${input_vcf} --output-maf output.maf --ref-fasta ${reference_fasta} \
    --vep-data ${vep_data} --ncbi-build GRCh38 --max-subpop-af 0.0005 \
    --vep-path /root/miniconda3/envs/vcf2maf/bin --maf-center "Sage Bionetworks"
  """

}

workflow {
  input_vcf_ch = Channel.fromPath(params.input_vcf)
  VCF2MAF(input_vcf_ch, params.reference_fasta, params.vep_data)
  VCF2MAF.out.view()
}
