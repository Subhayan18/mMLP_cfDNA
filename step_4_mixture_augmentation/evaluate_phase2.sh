#!/bin/bash
# Quick Evaluation Script for Phase 2
# Run this after Phase 2 training completes

cd /.../step_4_mixture_augmentation

# Load environment
source /.../step_2_model_architecture/LMOD.sourceme

# Run evaluation
python3 evaluate_deconvolution.py \
    --checkpoint /.../mixture_deconvolution_results/phase2_multitissue/checkpoints/checkpoint_best.pt \
    --test_h5 /.../training_dataset/mixture_data/phase2_test_mixtures.h5 \
    --output_dir /.../mixture_deconvolution_results/phase2_multitissue/evaluation \
    --device cuda \
    --batch_size 32

echo ""
echo "Evaluation complete!"
echo "Results saved to: /.../mixture_deconvolution_results/phase2_multitissue/evaluation"
echo ""
echo "View report:"
echo "  cat /.../mixture_deconvolution_results/phase2_multitissue/evaluation/evaluation_report.txt"
echo ""
echo "View figures:"
echo "  ls /.../mixture_deconvolution_results/phase2_multitissue/evaluation/figures/"
