#!/bin/bash
# Quick Evaluation Script for Phase 1
# Run this after Phase 1 training completes

cd /.../step_4_mixture_augmentation

# Load environment
source /.../step_2_model_architecture/LMOD.sourceme

# Run evaluation
python3 evaluate_deconvolution.py \
    --checkpoint /.../mixture_deconvolution_results/phase1_2tissue/checkpoints/checkpoint_best.pt \
    --test_h5 /.../training_dataset/mixture_data/phase1_test_mixtures.h5 \
    --output_dir /.../mixture_deconvolution_results/phase1_2tissue/evaluation \
    --device cuda \
    --batch_size 32

echo ""
echo "Evaluation complete!"
echo "Results saved to: /.../mixture_deconvolution_results/phase1_2tissue/evaluation"
echo ""
echo "View report:"
echo "  cat /.../mixture_deconvolution_results/phase1_2tissue/evaluation/evaluation_report.txt"
echo ""
echo "View figures:"
echo "  ls /.../mixture_deconvolution_results/phase1_2tissue/evaluation/figures/"
