# Auto-config environment by Snowdar (2020-04-16)

# Note: please make sure your project path is just like kaldi/egs/xmuspeech/yourproject, where
# the project should be in sub-sub-sub-dir of kaldi root. If not, modify KALDI_ROOT by yourself.

# Use decode_symbolic_link.sh rather than ../../../ to get the KALDI_ROOT so that it could
# support the case that the project is linked by a symbolic and $PWD contains the symbolic.

export KALDI_ROOT=/home/maison2/kaldi
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=$PWD/subtools/kaldi/utils/:$KALDI_ROOT/tools/openfst/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh
export LC_ALL=C
