# Script: negative_controls_differential_expression_w_confidence_intervals.R

### SETUP =====================================================================

# Saving image for debugging
if (!file.exists("RDA_objects/negative_controls_differential_expression_w_confidence_intervals")) { dir.create("RDA_objects/negative_controls_differential_expression_w_confidence_intervals", recursive = TRUE) }
save.image(paste0("RDA_objects/negative_controls_differential_expression_w_confidence_intervals/", snakemake@wildcards$sample, ".rda"))
message("Saved Image")
# stop("Manually Stopped Program after Saving Image")

# Open log file to collect messages, warnings, and errors
log_filename <- snakemake@log[[1]]
log <- file(log_filename, open = "wt")
sink(log)
sink(log, type = "message")


### LOADING FILES =============================================================

message("Loading in packages")
suppressPackageStartupMessages({
  library(tidyverse)
  library(sceptre)
})

message("Loading input files")
gene_gRNA_group_pairs <- readRDS(snakemake@input$gene_gRNA_group_pairs)
gRNA_groups_table <- readRDS(snakemake@input$gRNA_groups_table)
metadata <- readRDS(snakemake@input$metadata)
dge <- readRDS(snakemake@input$dge)
perturb_status <- readRDS(snakemake@input$perturb_status)


### SET UP FOR NEGATIVE CONTROLS ==============================================

# Subset the gRNA_groups_table for non-targeting guides only and rename to "pseudo_negative_control_enhancer"
mod_gRNA_groups_table <- gRNA_groups_table %>%
  mutate(grna_target = case_when(
    grna_target == "non-targeting" ~ "pseudo_negative_control_enhancer",
    TRUE ~ grna_target
  ))

# Test all "pseudo_negative_control_enhancer" - gene pairs
mod_gene_gRNA_group_pairs <- data.frame(
  grna_target = "pseudo_negative_control_enhancer",
  response_id = gene_gRNA_group_pairs %>% pull(response_id) %>% unique()
)
mod_gene_gRNA_group_pairs <- rbind(mod_gene_gRNA_group_pairs, gene_gRNA_group_pairs)
  

### CREATE SCEPTRE OBJECT =====================================================

# Create sceptre_object
sceptre_object <- import_data(
  response_matrix = dge,
  grna_matrix = perturb_status,
  grna_target_data_frame = mod_gRNA_groups_table,
  moi = "high",
  extra_covariates = metadata
)

# Set analysis parameters
sceptre_object <- set_analysis_parameters(
  sceptre_object = sceptre_object,
  discovery_pairs = mod_gene_gRNA_group_pairs,
  side = "both",
  grna_integration_strategy = "union",
)


### RUN DIFFEX ================================================================

sceptre_object <- sceptre_object %>% 
  assign_grnas(method = "thresholding", threshold = 5) %>%
  run_qc() %>%
  run_discovery_analysis(parallel = FALSE)


### SAVE OUTPUT ===============================================================

# Create "plots" subdirectory inside dirname(snakemake@output$discovery_results)
plots_dir <- file.path(dirname(snakemake@output$discovery_results), "plots")
if (!dir.exists(plots_dir)) {
  dir.create(plots_dir, recursive = TRUE)
}

# Define ggsave wrapper for consistent usage
save_plot <- function(plot, file_name) {
  file_path <- file.path(plots_dir, paste0(file_name, ".pdf"))
  ggsave(
    filename = file_path,
    plot = plot,
    device = "pdf",
    width = 5,
    height = 5
  )
}

# Save plots with their respective names
message("Saving plots")
save_plot(plot_grna_count_distributions(sceptre_object), "plot_grna_count_distributions")
save_plot(plot_assign_grnas(sceptre_object), "plot_assign_grnas")
save_plot(plot_run_discovery_analysis(sceptre_object), "plot_run_discovery_analysis")
save_plot(plot_covariates(sceptre_object), "plot_covariates")
save_plot(plot_run_qc(sceptre_object), "plot_run_qc")

# Write all outputs to directory
message("Saving output files")
write_outputs_to_directory(sceptre_object, dirname(snakemake@output$discovery_results))

# Save the final sceptre object
saveRDS(sceptre_object, snakemake@output$final_sceptre_object)


### CLEAN UP ==================================================================

message("Closing log file")
sink()
sink(type = "message")
close(log)
