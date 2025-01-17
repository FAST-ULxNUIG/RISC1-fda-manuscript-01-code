# Load all helper functions: ----------------------------------------------
functions_path <- here::here("code", "functions")
results_path <- here::here("outputs", "results")
source(here::here("code", "simulation", "BFMM-paper-generate-simulated-data.R"))
source(file.path(functions_path, "BFMM-paper-simulation-fit-functions.R"))
source(file.path(functions_path, "BFMM-paper-helper-functions.R"))
source(file.path(functions_path, "functions-unstructured-covariance.R"))

# Set random seed for reproducibility: ------------------------------------
set.seed(1996)

# Fix some simulation parameters: -----------------------------------------
N_sub <- 280 # no. of subjects
J_rep <- 2 # number of replicate observation per subject
arg_vals <- 0:100 # time argument values
N_sim <- 500 # number of simulation replications in each scenario
B <- 1000 # No. of Bootstrap Replicates
N_simulation_MVN <- 10000
coverage_level_nominal <- 0.95 # (1 - alpha) level for simultaneous bands.
settings <- expand.grid(rep = seq_len(N_sim),
                        scenario = 1:2, # two-data generating scenarios considered
                        pc_var = c(0.9999)) # mfpc cutoff fixed at 99.99%
N_sim_total <- nrow(settings) # total number of simulations (no. of scenario x no. of replications)
ncores <- 7

# Get ground truth fixed effects function ---------------------------------
# (to compare with)
fixef_true <- sim_data_list$B_empirical_scores %*% t(sim_data_list$Phi)
rownames(fixef_true) <- c("(Intercept)", "sexfemale", "speed")
fixef_true["(Intercept)",] <- fixef_true["(Intercept)",] + sim_data_list$mean_eval_vec
icc_true <- sum(sim_data_list$q_vec) / sum(sim_data_list$q_vec, sim_data_list$s_vec)
# Set up objects to store simulation result: ------------------------------
#  store simulation seeds for reproducbility (Morris et al., 2019)
simulation_seeds <- vector("list", length = N_sim_total) 

# Array's for fixed effects estimates (on grid)
# and pointwise coverage:
cover_boot_sim_array <-
  cover_wald_sim_array <- 
  fixef_array <-
  fixef_array_freg <-
  cover_wald_pw_array <-
  cover_boot_pw_array <-
  array(NA, dim = c(2 * length(arg_vals), 3, N_sim_total))

# Name the objects to index by name of effect
# (safer than indexing by number)
dimnames(fixef_array)[[2]] <-
  dimnames(fixef_array_freg)[[2]] <-
  dimnames(cover_wald_pw_array)[[2]] <-
  dimnames(cover_boot_pw_array)[[2]] <-
  colnames(cover_boot_sim_array) <-
  colnames(cover_wald_sim_array) <-
  c("(Intercept)", "sexfemale", "speed")

# Arrays to store random effects and error covariances:
Q_array <- 
  S_array <- 
  Q_array_unstruc <-
  S_array_unstruc <- 
  array(NA, dim = c(2 * length(arg_vals), 2 * length(arg_vals), N_sim_total))

# vectors to store:
time_boot <- # time it takes to do bootstrap
  mv_functional_icc_vec <- # estimates of the ICC
  k_retain_vec <- # number of fpcs retained
  vector(mode = "integer", length = N_sim_total)

icc_coverage_quantile <- icc_coverage_normal <- vector(mode = "numeric", length = N_sim_total)

# ------------------------------------------------------------------------#
# START SIMULATION
# ------------------------------------------------------------------------#
for(i in seq_len(N_sim_total)) {
  
  simulation_seeds[[i]] <- .Random.seed # store random seed
  print(paste0("Iteration ", i))
  
  pc_var <- settings[i, "pc_var"]
  
  ###################################################
  # Part (1): Generate Simulated Data
  ###################################################
  sim_data_i <- if(settings[i, "scenario"] == 1) {
    generate_data_scenario_1(N = N_sub, J = J_rep)
  } else if(settings[i, "scenario"] == 2) {
    generate_data_scenario_2(N = N_sub, J = J_rep)
  } 
  
  
  ###################################################
  # Part (2): Obtain Unstructured Estimattes
  ###################################################
  # Prepare data for least squares regression to
  # get estimates of fixed effects under working
  # independence assumption.
  
  # basis to use for coefficient functions and functional response:
  bspl80 <- create.bspline.basis(rangeval = range(arg_vals), 
                                 nbasis = 80, 
                                 norder = 4)
  
  # list of scalar covariates:
  x_fd_list <- list(Intercept = rep(1, N_sub * J_rep),
                    sexfemale = ifelse(sim_data_i$df$sex == "male", 0, 1),
                    speed = sim_data_i$df$speed) 
  
  # bivariate functional response:
  y_fd_obj <- grid_to_bivariate_fd(Y = sim_data_i$Y,
                                   argvals = arg_vals,
                                   basis_obj = bspl80) 
  
  # functional parameter object for coefficient functions:
  beta_fd_par <- fdPar(fdobj = bspl80)
  beta_list <- replicate(n = length(x_fd_list), 
                         expr = beta_fd_par,
                         simplify = FALSE) 
  
  # do least squares regression (separately in each dimension):
  freg_hip <- fRegress(y = y_fd_obj[,1], xfdlist = x_fd_list, betalist = beta_list)
  freg_knee <- fRegress(y = y_fd_obj[,2], xfdlist = x_fd_list, betalist = beta_list)
  
  # store fixed effects (even though not of interest):
  fixef_array_freg[1:101, "(Intercept)" ,i] <- eval.fd(arg_vals, fdobj = freg_hip$betaestlist[[1]]$fd)
  fixef_array_freg[1:101, "sexfemale" ,i] <- eval.fd(arg_vals, fdobj = freg_hip$betaestlist[[2]]$fd)
  fixef_array_freg[1:101, "speed" ,i] <- eval.fd(arg_vals, fdobj = freg_hip$betaestlist[[3]]$fd)
  
  fixef_array_freg[102:202, "(Intercept)" ,i] <- eval.fd(arg_vals, fdobj = freg_knee$betaestlist[[1]]$fd)
  fixef_array_freg[102:202, "sexfemale" ,i] <- eval.fd(arg_vals, fdobj = freg_knee$betaestlist[[2]]$fd)
  fixef_array_freg[102:202, "speed" ,i] <- eval.fd(arg_vals, fdobj = freg_knee$betaestlist[[3]]$fd)

  
  
  # calculate residuals (i.e., center data around fixed effects)
  Y_centered_hip <- (freg_hip$yfdobj - freg_hip$yhatfdobj)
  Y_centered_knee <- (freg_knee$yfdobj - freg_knee$yhatfdobj)
  
  # obtain unstructured covariance estimates:
  unsturctured_cov <- cov_unstruc_mlfpca_bi_fd(
    fd_obj_list = list(Y_centered_hip, Y_centered_knee),
    id_vec =  as.integer(as.character(sim_data_i$df$subject_id))
    )
  
  # store unstructured covariance matrices:
  Q_array_unstruc[1:101, 1:101, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_U_bifd_list$K_U_11)
  Q_array_unstruc[1:101, 102:202, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_U_bifd_list$K_U_12)
  Q_array_unstruc[102:202, 1:101, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_U_bifd_list$K_U_21)
  Q_array_unstruc[102:202, 102:202, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_U_bifd_list$K_U_22)
  
  S_array_unstruc[1:101, 1:101, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_E_bifd_list$K_E_11)
  S_array_unstruc[1:101, 102:202, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_E_bifd_list$K_E_12)
  S_array_unstruc[102:202, 1:101, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_E_bifd_list$K_E_21)
  S_array_unstruc[102:202, 102:202, i] <- eval.bifd(arg_vals, arg_vals, unsturctured_cov$K_E_bifd_list$K_E_22)
  
  
  ###################################################
  # Part (3): Fit our functional mixed effects model:
  ###################################################
  
  # perform bfpca:
  bfpca_i <- do_bfpca(Y = sim_data_i$Y, 
                      argvals = arg_vals, 
                      pc_var_cutoff = pc_var)
  
  
  # extract results of bfpca:
  k_retain_i <- k_retain_vec[i] <- bfpca_i$k_retain
  Psi_hat <- bfpca_i$Psi_hat
  
  mean_eval_array_i <- eval.fd(0:100, bfpca_i$bfpca$meanfd)
  mean_eval_vec_i <- c(mean_eval_array_i[,,1], mean_eval_array_i[,,2])
  
  scores_i <- apply(bfpca_i$scores,
                    MARGIN = c(1, 2),
                    FUN = sum)
  

  colnames(scores_i) <- paste0("score_", seq_len(bfpca_i$k_retain))
  
  # create data frame of covariates and scores:
  lme_df_i <- cbind(sim_data_i$df, scores_i)
  
  # fit linear mixed effects model to each score independently
  lme_scores <- fit_lme_to_scores(lme_df = lme_df_i,
                                  fixef_formula = "sex + speed", 
                                  ranef_formula = "+ (1|subject_id)",
                                  REML = TRUE,
                                  k_retain = k_retain_i)
  
  
  ###################################################
  # Part (4): Extract and store estimates
  ###################################################
  # extract estimates:
  fixef_mat_i <- lme_scores$fixef_mat[c("(Intercept)", "sexfemale", "speed"), ]
  fixef_var_i <- lme_scores$fixef_var[c("(Intercept)", "sexfemale", "speed"), ]
  q_vec_i <- lme_scores$q_vec
  s_vec_i <- lme_scores$s_vec
  
  # store estimates:
  fixef_fun_point <- fixef_mat_i %*% t(Psi_hat) # Point Estimate
  fixef_fun_point["(Intercept)", ] <-  fixef_fun_point["(Intercept)", ] + mean_eval_vec_i
  fixef_array[,,i] <- t(fixef_fun_point) # Fixed Effects
  Q_array[,,i] <- Psi_hat %*% diag(q_vec_i) %*% t(Psi_hat) # RE Covariance
  S_array[,,i] <- Psi_hat %*% diag(s_vec_i) %*% t(Psi_hat) # Error Covariance
  mv_functional_icc_vec[i] <- sum(q_vec_i) / sum(s_vec_i, q_vec_i) # ICC
  
  
  ###################################################
  # Part (5): Compute confidence intervals
  ###################################################
  
  # ------------------------------------------------------------------------#
  # Wald:
  # ------------------------------------------------------------------------#

  # construct covariance functions of functional coefficients
  fixef_fun_covar <- lapply(
    c(`(Intercept)` = "(Intercept)", sexfemale = "sexfemale", speed ="speed"),
    function(x) {Psi_hat %*% diag(fixef_var_i[x, ]) %*% t(Psi_hat)
      }
    )
  
  # and then extract pointwise se from them:
  fixef_fun_se <- t(sapply(fixef_fun_covar, function(x) {
    sqrt(diag(x))
  }))
  
  
  wald_CI_int_sim <- mvn_sim(
    coef_point_est = fixef_mat_i["(Intercept)",, drop = TRUE], 
    coef_covar_mat = diag(fixef_var_i["(Intercept)",, drop = TRUE]), 
    Psi_basis = Psi_hat, 
    N_simulation_mvn = N_simulation_MVN,
    coverage_level = coverage_level_nominal)
  
  # construct simultaneous CIs by simulation:
  wald_CI_sex_sim <- mvn_sim(
    coef_point_est = fixef_mat_i["sexfemale",, drop = TRUE], 
    coef_covar_mat = diag(fixef_var_i["sexfemale",, drop = TRUE]), 
    Psi_basis = Psi_hat, 
    N_simulation_mvn = N_simulation_MVN,
    coverage_level = coverage_level_nominal)
  
  wald_CI_speed_sim <- mvn_sim(
    coef_point_est = fixef_mat_i["speed",, drop = TRUE], 
    coef_covar_mat = diag(fixef_var_i["speed",, drop = TRUE]), 
    Psi_basis = Psi_hat, 
    N_simulation_mvn = N_simulation_MVN,
    coverage_level = coverage_level_nominal)
  

    # store pointwise and simultaenous CIs:
  
  wald_CI_int <- list(
    pw = list(
      lower = fixef_fun_point["(Intercept)",, drop = TRUE] - 2 * fixef_fun_se["(Intercept)",, drop = TRUE],
      upper = fixef_fun_point["(Intercept)",, drop = TRUE] + 2 * fixef_fun_se["(Intercept)",, drop = TRUE]
    ),
    sim = list(
      lower =  mean_eval_vec_i + wald_CI_int_sim$lower, # need to add back on mean
      upper =  mean_eval_vec_i + wald_CI_int_sim$upper
    )
  )
  
  wald_CI_sex <- list(
    pw = list(
      lower = fixef_fun_point["sexfemale",, drop = TRUE] - 2 * fixef_fun_se["sexfemale",, drop = TRUE],
      upper = fixef_fun_point["sexfemale",, drop = TRUE] + 2 * fixef_fun_se["sexfemale",, drop = TRUE]
    ),
    sim = list(
      lower = wald_CI_sex_sim$lower,
      upper = wald_CI_sex_sim$upper
    )
  )
  
  wald_CI_speed <- list(
    pw = list(
      lower = fixef_fun_point["speed",, drop = TRUE] - 2 * fixef_fun_se["speed",, drop = TRUE],
      upper = fixef_fun_point["speed",, drop = TRUE] + 2 * fixef_fun_se["speed",, drop = TRUE]
    ),
    sim = list(
      lower = wald_CI_speed_sim$lower,
      upper = wald_CI_speed_sim$upper
    )
  )
  
  # ------------------------------------------------------------------------#
  # Bootstrap:
  # ------------------------------------------------------------------------#
  # Do the bootstrap of subjects (in parallel), record time taken:
  time_boot[i] <- system.time(
    boot_result <- bootstrap_of_subjects_coefs(lme_df = lme_df_i,
                                k_retain = k_retain_i,
                                fixef_formula = "sex + speed", 
                                ranef_formula = "+ (1|subject_id)",
                                REML = TRUE, 
                                B = B, # Degras (2017)
                                par_mc = TRUE,
                                n_cores = ncores))["elapsed"]
  # Extract the coefficient samples from the bootstrap:
  fixef_coef_samples_boot <- lapply(
    c(`(Intercept)` = "(Intercept)", sexfemale = "sexfemale", speed ="speed"),
    FUN = function(y) {
      t(sapply(boot_result, function(x) {
        x$fixef[y, ]
      }))
    }
  )
  # Obtain the bootstrap estimates of the coefficient covariance matrices:
  fixef_coef_covar_boot <- lapply(fixef_coef_samples_boot, var)
  # Combine with estimated bfpc basis to obtain bootstrap estimates
  # of the coefficient covariance functions:
  fixef_fun_se_boot <- lapply(c(`(Intercept)` = "(Intercept)", sexfemale = "sexfemale", speed ="speed"),
                              function(x) {
                                sqrt(diag(Psi_hat %*% fixef_coef_covar_boot[[x]] %*% t(Psi_hat)))
                                })
  # Again, cosntruct simultaneous bands by simulation from MVN
  # but this time, we use the bootstrap estimate of the coefficient covariance matrices
  sim_cb_bootstrap <- lapply(X = c(`(Intercept)` = "(Intercept)", sexfemale = "sexfemale", speed ="speed"),
                             FUN = function(x) {
    mvn_sim(coef_point_est = fixef_mat_i[x, , drop = TRUE],
            coef_covar_mat = fixef_coef_covar_boot[[x]],
            Psi_basis = Psi_hat,
            N_simulation_mvn = N_simulation_MVN, 
            coverage_level = coverage_level_nominal)
  })
  # extract results
  boot_CI_int_sim <- sim_cb_bootstrap[["(Intercept)"]]
  boot_CI_sex_sim <- sim_cb_bootstrap[["sexfemale"]]
  boot_CI_speed_sim <- sim_cb_bootstrap[["speed"]]
  # and store results
  boot_CI_int <- list(
    pw = list(
      lower = fixef_fun_point["(Intercept)",, drop = TRUE] - 2 * fixef_fun_se_boot[["(Intercept)"]],
      upper = fixef_fun_point["(Intercept)",, drop = TRUE] + 2 * fixef_fun_se_boot[["(Intercept)"]]
    ),
    sim = list(
      lower =  mean_eval_vec_i + boot_CI_int_sim$lower, # need to add back on mean
      upper =  mean_eval_vec_i + boot_CI_int_sim$upper
    )
  )
  
  boot_CI_sex <- list(
    pw = list(
      lower = fixef_fun_point["sexfemale",, drop = TRUE] - 2 * fixef_fun_se_boot[["sexfemale"]],
      upper = fixef_fun_point["sexfemale",, drop = TRUE] + 2 * fixef_fun_se_boot[["sexfemale"]]
    ),
    sim = list(
      lower = boot_CI_sex_sim$lower,
      upper = boot_CI_sex_sim$upper
    )
  )
  boot_CI_speed <- list(
    pw = list(
      lower = fixef_fun_point["speed",, drop = TRUE] - 2 * fixef_fun_se_boot[["speed"]],
      upper = fixef_fun_point["speed",, drop = TRUE] + 2 * fixef_fun_se_boot[["speed"]]
    ),
    sim = list(
      lower = boot_CI_speed_sim$lower,
      upper = boot_CI_speed_sim$upper
    )
  )
  
  
  ###################################################
  # Part (6): Assess and store coverage
  ###################################################
  
  # Store Pointwise Coverage of Pointwise Intervals:
  cover_wald_pw_array[,"(Intercept)",i] <-(wald_CI_int$pw$lower < fixef_true["(Intercept)",]) & (fixef_true["(Intercept)",] < wald_CI_int$pw$upper)
  cover_wald_pw_array[,"sexfemale",i] <-(wald_CI_sex$pw$lower < fixef_true["sexfemale",]) & (fixef_true["sexfemale",] < wald_CI_sex$pw$upper)
  cover_wald_pw_array[,"speed",i] <-(wald_CI_speed$pw$lower < fixef_true["speed",]) & (fixef_true["speed",] < wald_CI_speed$pw$upper)
  
  cover_boot_pw_array[,"(Intercept)",i] <-(boot_CI_int$pw$lower < fixef_true["(Intercept)",]) & (fixef_true["(Intercept)",] < boot_CI_int$pw$upper)
  cover_boot_pw_array[,"sexfemale",i] <-(boot_CI_sex$pw$lower < fixef_true["sexfemale",]) & (fixef_true["sexfemale",] < boot_CI_sex$pw$upper)
  cover_boot_pw_array[,"speed",i] <-(boot_CI_speed$pw$lower < fixef_true["speed",]) & (fixef_true["speed",] < boot_CI_speed$pw$upper)

  # Store Pointwise Coverage of Simultaneous Bands so that Simultaneous Coverage can be assessed later:
  cover_wald_sim_array[,"(Intercept)",i] <- (wald_CI_int$sim$lower < fixef_true["(Intercept)",]) & (fixef_true["(Intercept)",] < wald_CI_int$sim$upper)
  cover_wald_sim_array[,"sexfemale",i] <- (wald_CI_sex$sim$lower < fixef_true["sexfemale",]) & (fixef_true["sexfemale",] < wald_CI_sex$sim$upper)
  cover_wald_sim_array[,"speed",i] <- (wald_CI_speed$sim$lower < fixef_true["speed",]) & (fixef_true["speed",] < wald_CI_speed$sim$upper)
  
  cover_boot_sim_array[,"(Intercept)",i] <- (boot_CI_int$sim$lower < fixef_true["(Intercept)",]) & (fixef_true["(Intercept)",] < boot_CI_int$sim$upper)
  cover_boot_sim_array[,"sexfemale",i] <- (boot_CI_sex$sim$lower < fixef_true["sexfemale",]) & (fixef_true["sexfemale",] < boot_CI_sex$sim$upper)
  cover_boot_sim_array[,"speed",i] <- (boot_CI_speed$sim$lower < fixef_true["speed",]) & (fixef_true["speed",] < boot_CI_speed$sim$upper)

  ###################################################
  # Part (7): Bootstrap Interval for ICC:
  ###################################################
  boot_icc_i <- sapply(boot_result, FUN = function(x) {
    sum(x$q_vec) / sum(x$q_vec, x$s_vec)
  })
  
  icc_CI_boot_quantile <- quantile(boot_icc_i, probs = c(0.025, 0.975))
  icc_coverage_quantile[i] <- ((icc_true > icc_CI_boot_quantile[1]) & (icc_true < icc_CI_boot_quantile[2]))
  
  icc_SE_boot <- sd(boot_icc_i)
  icc_CI_boot_normal <- mv_functional_icc_vec[i] + c(-2, 2) * icc_SE_boot
  icc_coverage_normal[i] <- ((icc_true > icc_CI_boot_normal[1]) & (icc_true < icc_CI_boot_normal[2]))
  
  
  }
# ------------------------------------------------------------------------#
# END SIMULATION
# ------------------------------------------------------------------------#


# Store results: ----------------------------------------------------------
results_list <- list(
  fixef_estimates = list(fixef_array = fixef_array,
                         fixef_array_freg = fixef_array_freg), 
  settings = list(settings = settings,
                  arg_vals = arg_vals,
                  time_stamp = timestamp(),
                  sessionInfo = sessionInfo(),
                  seeds = simulation_seeds,
                  R.version = R.version),
  ranef = list(Q_array = Q_array,
               Q_array_unstruc = Q_array_unstruc,
               S_array = S_array,
               S_array_unstruc = S_array_unstruc,
               mv_functional_icc_vec = mv_functional_icc_vec,
               icc_coverage_quantile = icc_coverage_quantile,
               icc_coverage_normal = icc_coverage_normal),
  coverage = list(cover_boot_pw_array = cover_boot_pw_array,
                  cover_boot_sim_array = cover_boot_sim_array,
                  cover_wald_pw_array = cover_wald_pw_array,
                  cover_wald_sim_array = cover_wald_sim_array),
  truth = list(fixef_true = fixef_true,
               icc = icc_true,
               q_vec = sim_data_list$q_vec,
               s_vec = sim_data_list$s_vec)
  )


saveRDS(object = results_list, file.path(results_path, "BFMM-tidied-simulation-results.rds"))
