# Packages ----------------------------------------------------------------
library(ggplot2)    # CRAN v3.3.5
library(data.table) # CRAN v1.14.2
library(tikzDevice) # CRAN v0.12.3.1
library(ggpubr)     # CRAN v0.4.0

# File paths: -------------------------------------------------------------
functions_path <- here::here("code", "functions")
results_path <- here::here("outputs", "results")
plots_path <- here::here("outputs", "figures")

# Source scripts: ---------------------------------------------------------
source(here::here("code", # For some of the true simulation parameters
                  "simulation", 
                  "BFMM-paper-generate-simulated-data.R"))
source(file.path(functions_path, "theme_gunning.R"))


# Tweak some settings on plot: --------------------------------------------
theme_gunning()
theme_update(legend.title = element_text(size = 9, hjust = 0.5))
options(tikzLatexPackages = c(getOption( "tikzLatexPackages" ),"\\usepackage{amsfonts}"))
options(tikzLatexPackages = c(getOption( "tikzLatexPackages" ),"\\usepackage{amsmath}"))
options(tikzLatexPackages = c(getOption( "tikzLatexPackages" ),"\\usepackage{amssymb}"))
#          

# Rough guide for plot size: ----------------------------------------------
doc_width_cm <- 16
doc_width_inches <- doc_width_cm *  0.3937


# Load results: -----------------------------------------------------------
results_list <- readRDS(file.path(results_path,
                                  "BFMM-tidied-simulation-results.rds"))


# Extract Some Parameters: ------------------------------------------------
arg_vals <- results_list$settings$arg_vals
settings <- results_list$settings$settings
ranef_results <- results_list$ranef

# Fixed Effects Estimation -----------------------------------------------
fixef_array <- results_list$fixef_estimates$fixef_array
fixef_array_s1 <- fixef_array[,,settings$scenario == 1]
fixef_array_s2 <- fixef_array[,,settings$scenario == 2]
fixef_mat_true <- results_list$truth$fixef_true

## Initial visualisation -------------------------------------------------
# Rough, quick and dirty plots:
par(mfrow = c(2, 1))
matplot(fixef_array_s1[,1,],type = "l", col = "grey")
matplot(fixef_array_s2[,1,],type = "l", col = "grey")

par(mfrow = c(2, 1))
matplot(fixef_array_s1[,2,],type = "l", col = "grey")
matplot(fixef_array_s2[,2,],type = "l", col = "grey")

par(mfrow = c(2, 1))
matplot(fixef_array_s1[,3,],type = "l", col = "grey")
matplot(fixef_array_s2[,3,],type = "l", col = "grey")

# Not much difference in the scenarios. Different sampling variation 
# in the betas due to different covariance structures


## Look at estimation error -----------------------------------------------
fixef_error_s1 <- sweep(x = fixef_array_s1,
                        MARGIN =  c(1:2), 
                        STATS = t(fixef_mat_true),
                        FUN = "-",
                        check.margin = TRUE)

fixef_error_s2 <- sweep(x = fixef_array_s2,
                        MARGIN =  c(1:2), 
                        STATS = t(fixef_mat_true),
                        FUN = "-",
                        check.margin = TRUE)

# Rough plots:
par(mfrow = c(2, 1))
matplot(fixef_error_s1[,1,],type = "l", col = "grey")
title("Scenario 1")
matplot(fixef_error_s2[,1,],type = "l", col = "grey")
title("Scenario 2")

par(mfrow = c(2, 1))
matplot(fixef_error_s1[,2,],type = "l", col = "grey")
title("Scenario 1")
matplot(fixef_error_s2[,2,],type = "l", col = "grey")
title("Scenario 2")


par(mfrow = c(2, 1))
matplot(fixef_error_s1[,3,],type = "l", col = "grey")
title("Scenario 1")
matplot(fixef_error_s2[,3,],type = "l", col = "grey")
title("Scenario 2")



## Calculate ISEs (discrete approximation to the integral) ----------------
fixef_ise_s1 <- apply(fixef_error_s1, 
                      MARGIN = c(2:3),
                      function(x) {
                        sum(x^2)
                        })

fixef_ise_s2 <- apply(fixef_error_s2, 
                      MARGIN = c(2:3),
                      function(x) {
                        sum(x^2)
                      })



## Get ISEs for plotting --------------------------------------------------
plot_ise_beta_dt <- data.table(
  scenario = factor(rep(c(1, 2), each = 500)),
  rbind(t(fixef_ise_s1), t(fixef_ise_s2)))

plot_ise_beta_dt_lng <- melt.data.table(
  plot_ise_beta_dt, id.vars = c("scenario"), 
  measure.vars = c("(Intercept)", "sexfemale", "speed"), 
  variable.name = "parameter",
  value.name = "ise",
  variable.factor = FALSE, 
  value.factor = FALSE,
  verbose = TRUE)

plot_ise_beta_dt_lng[, param_name := 
                       fcase(
                         parameter == "(Intercept)", "$\\boldsymbol{\\beta}_0(t)$",
                         parameter == "sexfemale", "$\\boldsymbol{\\beta}_1 (t)$",
                         parameter == "speed", "$\\boldsymbol{\\beta}_2 (t)$"
                       )]

p1 <- ggplot(data = plot_ise_beta_dt_lng) +
  aes(fill = scenario, x = scenario, y = ise) +
  facet_wrap(~ param_name, nrow = 1, ncol = 3, scales = "free_y") +
  geom_boxplot() +
  labs(x = "Scenario",
       title = "Fixed Effects",
       fill = "Scenario",
       y = "ISE") +
  theme(legend.position = "none")

p1


## Look at bias -----------------------------------------------------------
# again, quick and dirty, we used a near-lossless transformation so this
# should be small in all cases:

bias_s1 <- apply(fixef_array_s1, c(1,2), mean) - t(fixef_mat_true)

bias_s2 <- apply(fixef_array_s2, c(1,2), mean) - t(fixef_mat_true)

par(mfrow = c(2, 1))
plot(bias_s1[,1]^2, col = 1, type = "l", 
     ylim = range(
       bias_s1[,1]^2,
       bias_s2[,1]^2
     ))
lines(bias_s2[,1]^2, col = 2)

plot(bias_s1[,2]^2, col = 1, type = "l", 
     ylim = range(
       bias_s1[,2]^2,
       bias_s2[,2]^2
     ))
lines(bias_s2[,2]^2, col = 2)

plot(bias_s1[,3]^2, col = 1, type = "l", 
     ylim = range(
       bias_s1[,3]^2,
       bias_s2[,3]^2
     ))
lines(bias_s2[,3]^2, col = 2)
dev.off() # close plotting window
# bias is small in both cases



# Functional ICC ----------------------------------------------------------

# get true s's and q's (ideally these be saved from simulation avopid loading)
icc_plot_dt <- data.table(scenario = factor(rep(c(1, 2), each = 500)),
                          icc = ranef_results[[5]])
icc_truth <- sum(results_list$truth$q_vec) / sum(results_list$truth$q_vec, results_list$truth$s_vec)

ggplot(data = icc_plot_dt) +
  aes(fill = scenario, x= scenario, y = icc) +
  geom_boxplot() +
  geom_hline(yintercept = icc_truth) +
  labs(y = "Estimated ICC",
       x = "Scenario",
       fill = "Scenario")

p2 <- ggplot(data = icc_plot_dt) +
  aes(fill = scenario, x= scenario, y = icc) +
  geom_boxplot() +
  geom_hline(yintercept = icc_truth) +
  labs(y = "Estimated ICC",
       title = "Intraclass Correlation Coefficient",
       x = "Scenario",
       fill = "Scenario")

p2

icc_plot_dt[, .(sqrt(mean((icc - icc_truth)^2))), by = .(scenario)]
# ICC estimnated well in both cases:



# Covariance Estimates ----------------------------------------------------
## Extract estimates: ------------------------------------------------------
# Truths:
q_true <- results_list$truth$q_vec
s_true <- results_list$truth$s_vec

Phi_true <- sim_data_list$Phi

Q_true_s1 <- Phi_true %*% diag(q_true) %*% t(Phi_true)
Q_true_s2 <- efuns_s2$efuns_U %*% diag(q_true) %*% t(efuns_s2$efuns_U)

S_true_s1 <- Phi_true %*% diag(s_true) %*% t(Phi_true)
S_true_s2 <- efuns_s2$efuns_E %*% diag(s_true) %*% t(efuns_s2$efuns_E)

# Model and unstructures estimates:
Q_array <- ranef_results$Q_array
S_array <- ranef_results$S_array

Q_array_unstruc <- ranef_results$Q_array_unstruc
S_array_unstruc <- ranef_results$S_array_unstruc

Q_array_s1 <- Q_array[,, settings$scenario == 1]
Q_array_s2 <- Q_array[,, settings$scenario == 2]

S_array_s1 <- S_array[,, settings$scenario == 1]
S_array_s2 <- S_array[,, settings$scenario == 2]

Q_array_unstruc_s1 <- Q_array_unstruc[,, settings$scenario == 1]
Q_array_unstruc_s2 <- Q_array_unstruc[,, settings$scenario == 2]

S_array_unstruc_s1 <- S_array_unstruc[,, settings$scenario == 1]
S_array_unstruc_s2 <- S_array_unstruc[,, settings$scenario == 2]


## Look at Q first --------------------------------------------------------

# Calculate Errors:
Q_error_s1 <- sweep(Q_array_s1,
                    MARGIN = c(1:2), 
                    STATS = Q_true_s1,
                    FUN = "-", 
                    check.margin = TRUE)

Q_error_s2 <- sweep(Q_array_s2,
                    MARGIN = c(1:2), 
                    STATS = Q_true_s2,
                    FUN = "-", 
                    check.margin = TRUE)

Q_error_unstruc_s1 <- sweep(Q_array_unstruc_s1,
                            MARGIN = c(1:2), 
                            STATS = Q_true_s1,
                            FUN = "-", 
                            check.margin = TRUE)

Q_error_unstruc_s2 <- sweep(Q_array_unstruc_s2,
                            MARGIN = c(1:2), 
                            STATS = Q_true_s2,
                            FUN = "-",
                            check.margin = TRUE)

ise_Q_s1 <- apply(Q_error_s1,
                  MARGIN = c(3),
                  FUN = function(x) {
                    sum(x^2)
                    })

ise_Q_s2 <- apply(Q_error_s2,
                  MARGIN = c(3),
                  FUN = function(x) {
                    sum(x^2)
                    })

ise_Q_unstruc_s1 <- apply(Q_error_unstruc_s1,
                          MARGIN = c(3), 
                          FUN = function(x) {
                            sum(x^2)
                            })

ise_Q_unstruc_s2 <- apply(Q_error_unstruc_s2,
                          MARGIN = c(3), 
                          FUN = function(x) {
                            sum(x^2)
                            })

# Quick and dirty plot, we'll tidy later!
boxplot(ise_Q_s1, ise_Q_unstruc_s1, ise_Q_s2, ise_Q_unstruc_s2)


# S -----------------------------------------------------------------------
# calculate errors:
S_error_s1 <- sweep(S_array_s1, MARGIN = c(1:2), 
                    STATS = S_true_s1,
                    FUN = "-", 
                    check.margin = TRUE)

S_error_s2 <- sweep(S_array_s2, MARGIN = c(1:2), 
                    STATS = S_true_s2,
                    FUN = "-", check.margin = TRUE)


S_error_unstruc_s1 <- sweep(S_array_unstruc_s1, MARGIN = c(1:2), 
                            STATS = S_true_s1,
                            FUN = "-", 
                            check.margin = TRUE)

S_error_unstruc_s2 <- sweep(S_array_unstruc_s2, MARGIN = c(1:2), 
                            STATS = S_true_s2,
                            FUN = "-", check.margin = TRUE)

# and ISEs from integrals using discrete approximation:
ise_S_s1 <- apply(S_error_s1,
                  MARGIN = c(3),
                  FUN = function(x) {
                    sum(x^2)
                    })

ise_S_s2 <- apply(S_error_s2,
                  MARGIN = c(3),
                  FUN = function(x) {
                    sum(x^2)
                    })

ise_S_unstruc_s1 <- apply(S_error_unstruc_s1, 
                          MARGIN = c(3),
                          FUN = function(x) {
                            sum(x^2)
                            })

ise_S_unstruc_s2 <- apply(S_error_unstruc_s2,
                          MARGIN = c(3), 
                          FUN = function(x) {
                            sum(x^2)
                            })




cov_results_dt <- data.table(
  scenario = factor(rep(1:2, each = 1000)),
  method = factor(rep(rep(c("Structured", "Unstructured"), each = 500), times = 2)),
  ise_Q = c(
    ise_Q_s1, 
    ise_Q_unstruc_s1,
    ise_Q_s2, 
    ise_Q_unstruc_s2
  ),
  ise_S = c(
    ise_S_s1, 
    ise_S_unstruc_s1,
    ise_S_s2, 
    ise_S_unstruc_s2
  )
)

## Re-shape for plotting in publiash-able figure -------------------------

cov_results_dt_lng <- melt.data.table(
  cov_results_dt,
  id.vars = c("scenario", "method"), 
  measure.vars = c("ise_Q", "ise_S"), 
  variable.name = "paramater", 
  value.name = "ise",
  variable.factor = "false", 
  value.factor = "false",
  verbose = TRUE
)

cov_results_dt_lng[, param_name := fifelse(
  paramater == "ise_Q",
  "$\\textbf{Q}(t, t')$",
  "$\\textbf{S}(t, t')$"
)]


p3 <- ggplot(data = cov_results_dt_lng) +
  aes(fill = scenario, x = scenario, y = ise / 10^6, colour = method) +
  facet_wrap( ~ param_name, scales = "free_y") +
  scale_linetype_manual(values = c(1, 3)) +
  scale_color_manual(name = "", values = c("black", "darkgrey")) +
  geom_boxplot() +
  labs(y = "ISE / $10^{-6}$",
       title = "Covariance Functions",
       x = "Scenario",
       fill = "Scenario") +
  theme(legend.position = "none", plot.margin = margin(l = 12, r =0.1, b = 5))
p3



# Re-do previous figure to combine ----------------------------------------
p2 <- ggplot(data = icc_plot_dt) +
  aes(fill = scenario, x= scenario, y = icc) +
  geom_boxplot() +
  geom_hline(yintercept = icc_truth) +
  labs(y = "Estimated ICC",
       title = "Intraclass Correlation Coefficient",
       x = "Scenario",
       fill = "Scenario") +
  theme(legend.position = "none", 
        plot.title = element_text(margin = margin(b = 6, t = -5)))

p2

# combine plots 2 and 3:
p2.5 <- ggarrange(p3, p2, nrow = 1, ncol = 2, widths = c(0.675, 0.325)) # using `patchwork`



(combined_plot <- ggarrange(plotlist = 
            list(
              p1, p2.5
            ), ncol = 1, nrow = 2))




tikz(file.path(plots_path, "simulation-results-plot.tex"),
     width = 1.5 * doc_width_inches, 
     height = 1 * doc_width_inches)
print(combined_plot)
dev.off()








