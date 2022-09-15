# nf-vcf2maf

Annotate VCF files using VEP and generate MAF files using vcf2maf

## Setup

```console
# Install tmux for long-running commands
sudo yum install -y tmux

# Download Ensembl VEP cache (expands to 22G)
mkdir -p $HOME/ref/ $HOME/.vep/
rsync -avr --progress rsync://ftp.ensembl.org/ensembl/pub/release-107/variation/indexed_vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz $HOME/ref/
tar -zvxf $HOME/ref/homo_sapiens_vep_107_GRCh38.tar.gz -C $HOME/.vep/

# Download reference genome FASTA file
mkdir -p $HOME/ref/fasta/
aws --no-sign-request s3 sync s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/ $HOME/ref/fasta/

# Get example VCF file for testing purposes
mkdir -p $HOME/data
echo "Log into AWS using credentials from JumpCloud"
aws s3 cp s3://ntap-add5-project-tower-bucket/outputs/sarek_syn29793238/VariantCalling/2-001_Plexiform_Neurofibroma/DeepVariant/2-001_Plexiform_Neurofibroma.vcf.gz ~/data/test.vcf.gz
gunzip ~/data/test.vcf.gz
head -n 4000 ~/data/test.vcf ~/data/test-small.vcf

# Install and setup Nextflow
sudo yum install -y java
(cd .local/bin && wget -qO- https://get.nextflow.io | bash)
echo 'export NXF_ENABLE_SECRETS=true' >> ~/.bashrc
source ~/.bashrc
nextflow secrets put -n SYNAPSE_AUTH_TOKEN -v "<synapse-pat>"

# Stage reference files in memory
mkdir -p /dev/shm/vep/ /dev/shm/fasta/
sudo mount -o remount,size=30G /dev/shm  # Increase /dev/shm size
rsync -avhP $HOME/.vep/ /dev/shm/vep/
rsync -avhP $HOME/ref/fasta/ /dev/shm/fasta/
```
