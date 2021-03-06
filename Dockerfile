FROM nfcore/base:1.9
LABEL authors="Steffen Lemke" \
      description="Docker image containing all requirements for steffenlem/querysra pipeline"

# Install the conda environment
COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a

# Add conda installation dir to PATH (instead of doing 'conda activate')
ENV PATH /opt/conda/envs/nf-core-querysra-0.1dev/bin:$PATH

# Dump the details of the installed packages to a file for posterity
RUN conda env export --name nf-core-querysra-0.1dev > nf-core-querysra-0.1dev.yml
