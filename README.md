# ISSAC - Interpretability of Speech Signal under Adverse Conditions - Language ID
GitHub Link: https://github.com/TonnyTran/ISSAC_LanguageID

## Installation:
### Setting up environment
1) Install Kaldi
```bash
git clone -b 5.4 https://github.com/kaldi-asr/kaldi.git kaldi
cd kaldi/tools/; 
# Run this next line to check for dependencies, and then install them
extras/check_dependencies.sh
make; cd ../src; ./configure; make depend; make
```
2) Install EspNet
```bash
git clone -b v.0.9.7 https://github.com/espnet/espnet.git
cd espnet/tools/        # change to tools folder
ln -s {kaldi_root}      # Create link to Kaldi. e.g. ln -s home/theanhtran/kaldi/
```
3) Set up Conda environment
```bash
./setup_anaconda.sh anaconda espnet 3.7.9   # Create a anaconda environmetn - espnet with Python 3.7.9
make TH_VERSION=1.8.0 CUDA_VERSION=10.2     # Install Pytorch and CUDA
. ./activate_python.sh; python3 check_install.py  # Check the installation
conda install torchvision==0.9.0 torchaudio==0.8.0 -c pytorch
```
<!-- conda install pytorch==1.7.1 torchvision==0.8.2 torchaudio==0.7.2 cudatoolkit=10.2 -c pytorch -->
4) Install Kaldi IO
```bash
conda install kaldi_io
```

### Download the project
1) Clone the project from GitHub into your workspace
```bash
git clone https://github.com/TonnyTran/ISSAC_LanguageID
```
2) Point to your espnet

Open `ISSAC_LanguageID/path.sh` file, change $MAIN_ROOT$ to your espnet directory, e.g. `MAIN_ROOT=/home/theanhtran/espnet`

## How to run Language ID systems
1. Data preparation step
Open `ISSAC_LanguageID/prepare_data.sh` file, update raw LRE 2017 data location of train, dev and test set
```bash
bash prepare_data.sh --steps 1-6     # we can run step by step
```

2. Run the program: train Kaldi x-vector baseline
```bash
bash baseline_xvector.sh --steps 1-7
```

3. Test the pretrained model: Kaldi x-vector baseline
```bash
bash test.sh --steps 1-2
```

