##################################################
## Project: Strategic Voting in RCV
## Script purpose: Replication of Andy's plots
##					 in the CSES case
## Date: 25/11/2018
## Author:
##################################################

###
### Dependencies
###

# Set WD etc.
library(here)

# Load pivotal probability functions:
av_piv_path <- here("utils/av_pivotal_probs_analytical_general_v2.r")
source(av_piv_path)
plur_piv_path <- here("utils/plurality_pivotal_probabilities_analytical.r")
source(plur_piv_path)

# To replicate Andy's function(s):
sim_appr2 <- here("utils", "general_iteration_simulation_approach.r")
source(sim_appr2)
sv_file <-  here("utils/sv.r")
source(sv_file)

# Load my own functions:
functions <- here("utils/functions.r")
source(functions)

# Load necessary libraries:
library(ggplot2)
library(reshape2)
library(dplyr)
library(purrr)
library(tidyr)
library(ggtern)
library(lmtest)
library(sandwich)
library(plm)
library(extrafont)
library(RColorBrewer)

# Load CSES data:
load(here("../output/cses_big_list_2.RData"))

# Load font
font_import()
fonttable()
# font_import(paths = "~/.local/share/fonts/", prompt = F)

# Specify ggplot2 theme

theme_sv <- function(){
  theme_bw(base_size=11, base_family="Roboto Light") %+replace%
  theme(
    panel.grid.major =  element_line(
      colour = "grey50", 
      size = 0.2,
      linetype = "dotted"),
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "grey97"),
    plot.margin = unit(c(0.2, 1, 0.2, 1), "cm"),
    legend.margin = margin(0, 0, 0, 0),
    legend.title = element_text(size = 10, family = "Roboto Medium", face = "bold"),
    strip.background = element_rect(fill= NULL, colour = "white", linetype = NULL), 
    strip.text = element_text(colour = 'grey50', size = 9, vjust = 0.5, family = "Roboto Medium")
  )
}
  
remove_nas <- function(x){
  mat <- cbind(x$U, x$weights)
  mat <- na.omit(mat)
  return(list(U = mat[, 1:3], weights = as.numeric(mat[, 4])))
}

create_v_vec <- function(x){
  x$U <- x$U + runif(nrow(x$U) * ncol(x$U), min = 0, max = 0.001)
  sin_vote <- as.numeric(apply(x$U, 1, function(x) sin_vote_scalar(x)))
  num_list <- c(1:6)
  sin_df <- (sapply(num_list, function(x) as.numeric(sin_vote == x)))
  sin_df <- sin_df * x$weights
  sin_vec <- colSums(sin_df)
  return(sin_vec / sum(sin_vec))
}

# Create list with v_vecs from CSES utility dfs:
big_list_na_omit <- lapply(big_list, function(x) remove_nas(x))
sin_vote_list <- lapply(big_list_na_omit, function(x) sincere.vote.mat.from.U(x$U, rule = "AV"))
v_vec_list <- list()
for(i in 1:length(sin_vote_list)){
  weights <- big_list_na_omit[[i]]$weights
  v_vec <- ballot.props.from.vote.mat.and.weights(sin_vote_list[[i]], weights)
  big_list_na_omit[[i]]$v_vec <- as.numeric(v_vec)
}

# Set list of s values
s_list <- as.list(c(15, 30, 45, 60, 75, 85, 90))

# Drop NA cases
names(big_list)[[39]]
names(big_list)[[145]]
big_list_na_omit[[39]] <- NULL
big_list_na_omit[[144]] <- NULL

# Import VAP data
vap <- read.csv(here("../data/case_vap.csv"), sep = "")

# Loop that creates the tau objects
# uses my own function -- see below for faster implementation
# sv_list <- list()
# for(i in 1:length(big_list_na_omit)){
#   print(i)
#   sv_list[[i]] <- return_sv_tau(c(big_list_na_omit[[i]]$v_vec, 0, 0, 0), big_list_na_omit[[i]]$U, s_list)
# }

###
### DESCRIPTIVE
###

v_vec_df <- matrix(NA, nrow = 160, ncol = 6)
simplex_df <- matrix(NA, nrow = 160, ncol = 3)
for(i in 1:length(big_list_na_omit)){
  v_vec <- big_list_na_omit[[i]]$v_vec
  simplex_vec <- c(v_vec[1] + v_vec[2], v_vec[3] + v_vec[4], v_vec[5] + v_vec[6])
  v_vec_df[i, ] <- as.numeric(v_vec)
  simplex_df[i, ] <- simplex_vec
}
simplex_df <- as.data.frame(simplex_df)
names(simplex_df) <- c("A", "B", "C")

# ggtern(simplex_df, aes(A, B, C)) +
#   geom_point()

# Distribution of second preferences
second_prefs <- data.frame(mAB = v_vec_df[, 1] / (v_vec_df[, 1] + v_vec_df[, 2]), mBA = v_vec_df[, 3] / (v_vec_df[, 3] + v_vec_df[, 4]), mCB = v_vec_df[, 6] / (v_vec_df[, 5] + v_vec_df[, 6]))

# ggplot(second_prefs, aes(mAB, mCB)) +
#   geom_point() +
#   geom_smooth(method = "loess") +
#   theme_bw()

# Get classification
class_vec <- apply(v_vec_df, 1, classify.vec)

# How else to summarise? Fit line (mAB/mCB) and describe cases by residuals.

###
### ANALYSIS
###

# Use Andy's function to create list of sv objects for each case
sv_list <- list()
for(i in 1:length(big_list_na_omit)){
  print(i)
  this_list <- big_list_na_omit[[i]]
  df_list <- lapply(s_list, function(x) convert_andy_to_sv_item_two(this_list$U, this_list$weights, x, this_list$v_vec))
  df <- as.data.frame(do.call(rbind, df_list))
  df$case <- names(big_list_na_omit)[[i]]
  df$weight <- big_list_na_omit[[i]]$weights
  df$country <- substr(df$case, 1, 3)
  df$weight_sum <- sum(big_list_na_omit[[i]]$weights)
  df$VAP <- vap$VAP[vap$cntry == df$country[1]]
  df$m <- vap$Freq[vap$cntry == df$country[1]]
  df$weight_rep <- df$weight * (df$VAP / (df$weight_sum * df$m))
  #df <- apply(df, 2, as.numeric)
  sv_list[[i]] <- df
}

####

# Check whether they really do produce the same as Andy's function!
# test_toby <- return_sv_tau(c(big_list_na_omit[[109]]$v_vec, 0, 0, 0), big_list_na_omit[[109]]$U, list(60))
# test_andy <- sv(U = big_list_na_omit[[109]]$U, weights = big_list_na_omit[[109]]$weights, s = 60, rule = "AV")
# # OK, what I need to do is to run the entire loop with Andy's function and check the entire DF for discrepancies.
#
# andy_list <- list()
# andy_list_prop <- list()
# for(i in 1:length(big_list)){
#   this_list <- big_list[[i]]
#   print(i)
#   sv_obj <- sv(U = this_list$U, weights = this_list$weights, s = 60, rule = "AV")
#   sv_obj_plur <- sv(U = this_list$U, weights = this_list$weights, s = 60)
#   andy_list[[i]] <- sv_obj
#   prop_av <- sum(sv_obj$weights[!is.na(sv_obj$tau) & sv_obj$tau > 0]) / sum(sv_obj$weights[!is.na(sv_obj$tau)])
#   prop_plur <- sum(sv_obj_plur$weights[!is.na(sv_obj_plur$tau) & sv_obj_plur$tau > 0]) / sum(sv_obj_plur$weights[!is.na(sv_obj$tau)])
#   andy_list_prop[[i]] <- c(prop_av, prop_plur)
# }
#
# andy_list_prop_df <- do.call(rbind, andy_list_prop)
#
# # compare:
# andy_list_prop_df == prop_df[prop_df$s == 60, c(8, 9)]

####

# save(file = here("../output/sv_list.Rdata"), sv_list)
# load(here("../output/sv_list.Rdata"))

# names(big_list)

## Additional analysis off the sv_obj cases

# (1) Proportion of optimal strategic votes
prop_list <- list()
for(i in 1:length(sv_list)){
  print(i)
  prop_list[[i]] <- sv_prop(sv_list[[i]], big_list_na_omit[[i]]$weights)
  df <- as.data.frame(prop_list[[i]])
  df$case <- as.character(names(big_list_na_omit)[[i]])
  df$class <- class_vec[i]
  df$s <- as.numeric(s_list)
  n <- apply(df[, 1:3], 1, function(x) sum(x))
  df[, 1:5] <- df[, 1:5] / sum(big_list_na_omit[[i]]$weights)
  prop_list[[i]] <- df
}
prop_df <- do.call(rbind, prop_list)
names(prop_df)[1:5] <- c("rcv_first", "rcv_second", "rcv_third", "plur_first", "plur_second")
prop_df_long <- melt(prop_df[, c(2, 3, 5, 6, 7, 8)], id.vars = c("case", "s", "class"))
prop_df_agg <- as.data.frame(prop_df_long %>%
                               group_by(variable, s) %>%
                               summarize(mean(value)))
names(prop_df_agg)[3] <- "value"

cses_prop <- ggplot(prop_df_long, aes(x = s, y = value)) +
  geom_line(aes(colour = variable, group = interaction(case, variable)), alpha = 0.05) +
  geom_line(data = prop_df_agg, aes(colour = variable, group = variable, x = s, y = value),
            size = 2) +
  labs(x = "Information (s)",
       y = "Proportion of voters in CSES (case) casting ballot type",
       colour = "Ballot order") +
  theme_sv() + 
  scale_color_brewer(palette = "Set2") +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0.1, 0), limits = c(0, 0.5)) +
  theme(legend.position = "bottom", legend.direction = "horizontal")
ggsave(here("../output/figures/cses_freq.pdf"), cses_prop, height = 4, width = 5, device = cairo_pdf)

# (2) Distribution of incentives (in scatterplot)
prop_df$inc_rcv <- prop_df$rcv_second + prop_df$rcv_third
prop_df$inc_plur <- prop_df$plur_second

prop_df$type <- NA
prop_df$type[grep("DM", prop_df$class)] <- "DM"
prop_df$type[grep("SP", prop_df$class)] <- "SP"

cses_inc <- ggplot(prop_df, aes(x = inc_plur, y = inc_rcv)) +
  geom_point(alpha = 0.2, color = "red") +
  geom_abline(slope = 1, intercept = 0) +
  facet_wrap(~ s, ncol = 4) +
  theme_sv() +
  scale_x_continuous(limits = c(0, 0.5), expand = c(0, 0)) +
  scale_y_continuous(limits = c(0, 0.5), expand = c(0, 0)) +
  labs(x = "Pr(tau_P > 0)",
       y = "Pr(tau_I > 0)")
ggsave(here("../output/figures/cses_prop.pdf"), cses_inc, width = 9, height = 5, device = cairo_pdf)

cses_inc_type <- ggplot(prop_df[prop_df$s == 85, ], aes(x = inc_plur, y = inc_rcv)) +
  geom_point(alpha = 0.5) +
  geom_abline(slope = 1, intercept = 0) +
  facet_wrap(~ class, ncol = 7) +
  theme_sv() +
  scale_x_continuous(limits = c(0, 0.5), expand = c(0, 0)) +
  scale_y_continuous(limits = c(0, 0.5), expand = c(0, 0)) +
  labs(x = "Proportion of CSES respondents with positive SI under Plurality",
       y = "Proportion of CSES respondents with positive SI under RCV")
ggsave(here("../output/figures/cses_prop_type.pdf"), cses_inc_type, width = 9, height = 5)


# Check proportions
rcv_big <- sapply(s_list, function(x)
  sum(prop_df$inc_rcv[prop_df$s == x] > prop_df$inc_plur[prop_df$s == x]))
rcv_big
160 - rcv_big
rcv_big/ 160


# 2(b) Produce key figure.


# Assemble DF (from all lists)
big_sv_df <- do.call(rbind, sv_list)
big_sv_df <- big_sv_df[big_sv_df$s == 85, ]

tau_df <- big_sv_df[, c(3, 4, 10, 16)] # Needs fixing since tilde columns added
tau_df$respondent <- 1:nrow(tau_df)
tau_df <- gather(tau_df, type, tau, 1:2)
# Strictly speaking redunant since we could use factor variable
tau_df$system <- 0
tau_df$system[tau_df$type == "tau_rcv"] <- 1

tau_df$system_plur <- 1 - tau_df$system

# Changing model specification to get estimates for both RCV and plurality

rcv_diff <- function(tau_df, epsilon){
  tau_df$above_epsilon <- tau_df$tau > epsilon 
  model <- lm("above_epsilon ~ system + system_plur - 1", data = tau_df, weights = tau_df$weight_rep)
  result <- coeftest(model, vcov = vcovHC(model, type = "HC0", cluster = "respondent"))
  return(c(result[1, 1], result[1, 2], result[2, 1], result[2, 2]))
}

epsilon_list <- list(0.00000001, 0.0000001, 0.000001, 0.00001, 0.0001, 0.0005, 0.001, 0.01, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.5, 2)
epsilon_results <- t(sapply(epsilon_list, function(x) rcv_diff(tau_df, x)))
epsilon_results <- as.data.frame(epsilon_results)

# To-Do: tidy data and rekindle plot such that it shows absolute proportions for both RCV and Plurality

names(epsilon_results) <- c("beta_zero", "se_zero", "beta_one", "se_one")
epsilon_results$epsilon <- unlist(epsilon_list)

epsilon_true_scale <- ggplot(epsilon_results, aes(x = epsilon, y = beta_one)) +
  geom_point() +
  geom_errorbar(aes(ymin = beta_one - 1.96 * se_one, ymax = beta_one + 1.96 * se_one)) +
  geom_hline(yintercept = 0, lty = "dotted") +
  theme_sv() + 
  labs(x = expression(epsilon), y = expression(paste(beta[1], ": Difference in proportion of ", tau > epsilon, " between RCV and Plurality")))
ggsave("../output/figures/epsilon_true_scale.pdf", epsilon_true_scale, width = 6, height = 4)

epsilon_factor_scale <- ggplot(epsilon_results, aes(x = as.factor(epsilon), y = beta_one)) +
  geom_point() +
  geom_errorbar(aes(ymin = beta_one - 1.96 * se_one, ymax = beta_one + 1.96 * se_one)) +
  geom_hline(yintercept = 0, lty = "dotted") +
  theme_sv()+
  labs(x = expression(epsilon), y = expression(paste(beta[1], ": Difference in proportion of ", tau > epsilon, " between RCV and Plurality")))
ggsave("../output/figures/epsilon_factor_scale.pdf", epsilon_factor_scale, width = 6, height = 4, device = cairo_pdf)

epsilon_proportions <- ggplot(epsilon_results, aes(x = epsilon)) +
  geom_line(aes(y = beta_zero)) + 
  geom_line(aes(y = beta_zero + beta_one), lty = "dotted") +
  theme_bw() +
  theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank()) +
  labs(x = expression(epsilon), y = expression(paste("Proportion of voters with ", tau > epsilon)))
ggsave("../output/figures/epsilon_proportions.pdf", epsilon_proportions, width = 6, height = 4)

## Do the same with tau tilde.

tau_tilde_df <- big_sv_df %>% select(tau_tilde_rcv, tau_tilde_plur, case, weight_rep)
tau_tilde_df$respondent <- 1:nrow(tau_tilde_df)
tau_tilde_df <- gather(tau_df, type, tau, 1:2)
# Strictly speaking redunant since we could use factor variable
tau_tilde_df$system <- 0
tau_tilde_df$system[tau_tilde_df$type == "tau_tilde_rcv"] <- 1

epsilon_tilde_results <- t(sapply(epsilon_list, function(x) rcv_diff(tau_tilde_df, x)))
epsilon_tilde_results <- as.data.frame(epsilon_tilde_results)
names(epsilon_tilde_results) <- c("beta_zero", "se_zero", "beta_one", "se_one")
epsilon_tilde_results$epsilon <- unlist(epsilon_list)

epsilon_tilde_true_scale <- ggplot(epsilon_tilde_results, aes(x = epsilon, y = beta_one)) +
  geom_point() +
  geom_errorbar(aes(ymin = beta_one - 1.96 * se_one, ymax = beta_one + 1.96 * se_one)) +
  geom_hline(yintercept = 0, lty = "dotted") +
  theme_bw() +
  theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank()) +
  labs(x = expression(epsilon), y = expression(paste(beta[1], ": Difference in proportion of ", tilde(tau) > epsilon, " between RCV and Plurality")))
ggsave("../output/figures/epsilon_tilde_true_scale.pdf", epsilon_tilde_true_scale, width = 6, height = 4)

epsilon_tilde_factor_scale <- ggplot(epsilon_tilde_results, aes(x = as.factor(epsilon), y = beta_one)) +
  geom_point() +
  geom_errorbar(aes(ymin = beta_one - 1.96 * se_one, ymax = beta_one + 1.96 * se_one)) +
  geom_hline(yintercept = 0, lty = "dotted") +
  theme_bw() +
  theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank()) +
  labs(x = expression(epsilon), y = expression(paste(beta[1], ": Difference in proportion of ", tilde(tau) > epsilon, " between RCV and Plurality")))
ggsave("../output/figures/epsilon_tilde_factor_scale.pdf", epsilon_tilde_factor_scale, width = 6, height = 4)


# Produce scatterplot - proportion v magnitude.
summary_df <- big_sv_df %>% group_by(case) %>% 
  summarize(mag_rcv = mean(tau_rcv[tau_rcv > 0]), mag_plur = mean(tau_plur[tau_plur > 0]), prop_rcv = sum(tau_rcv > 0)/length(tau_plur), prop_plur = sum(tau_plur > 0)/length(tau_plur), sd_rcv = sd(tau_rcv[tau_rcv > 0]), sd_plur = sd(tau_plur[tau_plur > 0]), size = sum(weight_rep))
summary_df_rcv <- summary_df[, c(1, 2, 4, 6, 8)]
names(summary_df_rcv) <- c("case", "mag", "prop", "sd", "size")
summary_df_plur <- summary_df[, c(1, 3, 5, 7, 8)]
names(summary_df_plur) <- c("case", "mag", "prop", "sd", "size")
summary_df <- rbind(summary_df_rcv, summary_df_plur)
summary_df$type <- rep(c("rcv", "Plurality"), each = 160)

summary_plot <- ggplot(summary_df, aes(prop, mag)) +
  geom_errorbar(aes(ymin = mag - 1.96 * sd, ymax = mag + 1.96 * sd, colour = type), alpha = 0.1, lwd = 1.5) +
  geom_point(aes(colour = type, size = size), alpha = 0.5) +
  theme_bw() +
  theme(
    text = element_text(family = "Roboto-Light", colour = "grey20"),
    strip.background = element_blank(),
    strip.text = element_text(hjust = 0),
    panel.grid.major =  element_line(
      colour = "grey50", 
      size = 0.2,
      linetype = "dotted"),
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "grey97"),
    plot.margin = unit(c(0, 1, 0, 1), "cm"),
    legend.margin = margin(0, 0, 0, 0),
    legend.title = element_text(size = 10, family = "Roboto-Bold")) + 
  scale_colour_brewer(name = "System", palette = "Set2") +
  scale_size_continuous(name = "Electorate") +
  labs(x = expression(paste("Pr(", tau > 0, ")"), family = "Roboto-Regular"), 
    y = expression(paste(symbol(E), "[", tau, "|", tau > 0, "]"), family = "Roboto-Regular")
    )
summary_plot
ggsave("../output/figures/summary_plot.pdf", width = 7, height = 4)


# Run regression

# Check alternative method of computing incentive proportions
# sv_prop_alt <- function(tau_obj, weights, s = 60){
#   tau_obj <- tau_obj[tau_obj$s == s, ]
#   inc_rcv <- sum(weights[tau_obj$tau_rcv > 0]) / sum(weights)
#   inc_plur <- sum(weights[tau_obj$tau_plur > 0]) / sum(weights)
#   return(c(inc_rcv, inc_plur))
# }
#
# prop_list_alt <- list()
# for(i in 1:length(sv_list)){
#   prop_list_alt[[i]] <- sv_prop_alt(sv_list[[i]], big_list_na_omit[[i]]$weights, 60)
# }
# prop_df_alt <- as.data.frame(do.call(rbind, prop_list_alt))
# ggplot(prop_df_alt, aes(V2, V1)) +
#   geom_point() +
#   geom_abline(slope = 1, intercept = 0) +
#   theme_bw() +
#   scale_x_continuous(limits = c(0, 0.7), expand = c(0, 0)) +
#   scale_y_continuous(limits = c(0, 0.7), expand = c(0, 0))

## (3) QQ-Plots

qq_mega_list <- list()
for(i in 1:length(sv_list)){
  print(i)
  x <- sv_list[[i]]
  utils <- big_list_na_omit[[i]]$U
  case <- names(big_list_na_omit)[[i]]
  qq <- qq_function_two(x, utils)
  qq$case <- case
  qq_mega_list[[i]] <- qq
}
qq_mega_df <- as.data.frame(do.call(rbind, qq_mega_list))
qq_mega_by_s <- split(qq_mega_df, qq_mega_df$s)
qq_agg <- lapply(as.list(names(qq_mega_by_s)), function(s) {
    z <- qq_mega_by_s[[s]]
    df <- as.data.frame(qqplot(x = z$x, y = z$y, plot.it = FALSE))
    df$s <- rep(s, nrow(df))
    return(df)
  })
qq_agg_df <- as.data.frame(do.call(rbind, qq_agg))
cses_qq <- ggplot(qq_mega_df, aes(x = x, y = y)) +
  geom_line(aes(x = x, y = y, group = case), alpha = 0.1) +
  geom_line(data = qq_agg_df, aes(x = x, y = y), colour = "red", lwd = 2) +
  geom_abline(intercept = 0, slope = 1, linetype = "dotted", colour = "blue") +
  theme_bw()  +
  facet_wrap(vars(s), ncol= 4) +
  xlim(-30, 30) + ylim(-30, 30)
ggsave(here("../output/figures/cses_qq.pdf"), cses_qq, width = 9, height = 6)


# (4) Voting paradoxes

# Condorcet Winner
  # Calculate
  cw_win_rcv <- list()
  cw_win_plur <- list()

  for(i in 1:length(sv_list)){
    print(i)
    v_zero <- gen_v_zero(sv_list[[i]]$sin_rcv[sv_list[[i]]$s == 85])
    v_opt_rcv <- gen_v_zero(sv_list[[i]]$opt_rcv[sv_list[[i]]$s == 85])[[1]]
    v_opt_plur <- gen_v_zero_plur(sv_list[[i]]$opt_plur[sv_list[[i]]$s == 85])
    cw_win_rcv[[i]] <- evaluate_success_of_CW_given_U_and_V.mat(U = big_list_na_omit[[i]]$U, V.mat = v_opt_rcv, V0 = v_zero[[1]], lambdas = c(.1, .2, .3, .4, .5), big_list_na_omit[[i]]$weights, rule = "AV", m = 300, M = 1000)
    cw_win_plur[[i]] <- evaluate_success_of_CW_given_U_and_V.mat(U = big_list_na_omit[[i]]$U, V.mat = v_opt_plur, V0 = v_zero[[2]], lambdas = c(.1, .2, .3, .4, .5), big_list_na_omit[[i]]$weights, rule = "plurality", m = 300, M = 1000)
  }

  # Plot
  cw_df_rcv <- as.data.frame(do.call(rbind, cw_win_rcv))
  cw_df_plur <- as.data.frame(do.call(rbind, cw_win_plur))

  cw_df_rcv$case <- names(big_list_na_omit)
  cw_df_plur$case <- names(big_list_na_omit)
  names(cw_df_rcv)[1:5] <- c("0.1", "0.2", "0.3", "0.4", "0.5")
  names(cw_df_plur)[1:5] <- c("0.1", "0.2", "0.3", "0.4", "0.5")

  cw_df_rcv <- melt(cw_df_rcv, 6)
  cw_df_rcv$type <- "rcv"
  cw_df_plur <- melt(cw_df_plur, 6)
  cw_df_plur$type <- "Plurality"
  cw_df <- rbind(cw_df_rcv, cw_df_plur)

  cw_df_agg <- cw_df %>% group_by(type, variable) %>% summarise(mean(value))
  names(cw_df_agg)[3] <- "value"

  cond <- ggplot(cw_df, aes(variable, value)) +
    geom_line(aes(group = interaction(case, type), colour = type), alpha = 0.1) +
    geom_line(data = cw_df_agg, aes(group = type, colour = type), lwd = 2) +
    labs(x = "lambda", y = "Pr(Condorcet Winner elected)") +
    scale_colour_brewer(palette = "Set2") +
    theme_sv()
  ggsave(here("../output/figures/condorcet_probs.pdf"), width = 6, height = 4, device = cairo_pdf)

# Incidence of voting paradoxes

s <- 85 # Set level at which to evaluate

paradox_df <- matrix(NA, ncol = 3, nrow = length(big_list_na_omit))
for(i in 1:length(big_list_na_omit)){
  print(i)
  v_vec <- big_list_na_omit[[i]]$v_vec
  pprobs_rcv <- av.pivotal.event.probs.general(c(v_vec, 0, 0, 0), rep(s, 4))
  par_rcv <- non_monoton(sv_list[[i]][sv_list[[i]]$s == s, ], pprobs_rcv, weights = big_list_na_omit[[i]]$weights)
  v_vec_plur <- c(v_vec[1] + v_vec[2], v_vec[3] + v_vec[4], v_vec[5] + v_vec[6])
  pprobs_plur <- plurality.pivotal.probabilities(v_vec_plur, s)
  par_plur <- wasted_vote(sv_list[[i]][sv_list[[i]]$s == s, ], pprobs_plur, big_list_na_omit[[i]]$weights)

  no_show <- par_rcv$no_show / par_rcv$total
  nonmon <- (par_rcv$nonmon1 + par_rcv$nonmon2) / par_rcv$total
  wasted <- par_plur$wasted / par_plur$total
  paradox_df[i, ] <- c(no_show, nonmon, wasted)
}

paradox_df <- as.data.frame(paradox_df)
names(paradox_df) <- c("no_show", "nonmon", "wasted")

ggplot(paradox_df, aes(x = wasted)) +
  geom_point(aes(y = no_show, colour = "No-show"), size = 1.5, alpha = 0.2) +
  geom_point(aes(y = nonmon, colour = "Non-mon"), size = 1.5, alpha = 0.2) +
  geom_abline(intercept = 0, slope = 1, lty = "dotted") +
  geom_smooth(method = "loess", aes(y = no_show), colour = "blue") +
  geom_smooth(method = "loess", aes(y = nonmon), colour = "red") +
  xlim(0, 0.4) + ylim(0, 0.4) +
  labs(x = "Pr(Wasted Vote, Plurality)", y = "Pr(Voting Paradox, RCV)", colour = "Paradox type") +
  scale_colour_manual(breaks = c("No-show", "Non-mon"), values = c("No-show" = "blue", "Non-mon" = "red")) +
  theme_bw() +
  theme(legend.position = "bottom", legend.direction = "horizontal")
ggsave(here("../output/figures/paradoxes_cses.pdf"), height = 4, width = 4)

# (5) Interdependence

s <- 85 # Set level at which to evaluate
sv_list_fixed_s <- lapply(sv_list, function(x) x[x$s == s, ])

lambda_list <- as.list(seq(0, 0.5, 0.05))

inter_list <- list()
for(i in 1:length(big_list_na_omit)){
  print(i)
  df <- big_list_na_omit[[i]]
  sv_item <- sv_list_fixed_s[[i]]
  out <- level_two_props_cses(c(df$v_vec, 0, 0, 0), lambda_list, df$U, sv_item, s, df$weights)
  out$case <- names(big_list_na_omit)[[i]]
  inter_list[[i]] <- out
}

inter_df <- do.call(rbind, inter_list)

pal2 <- brewer.pal(n = 3, name = "Set2")

inter_df_agg <- as.data.frame(inter_df %>% group_by(lambda) %>% summarize(mean(L1RCV), mean(L1PLUR), mean(L0RCV), mean(L0PLUR)))
names(inter_df_agg) <- c("lambda", "l1rcv", "l1plur", "l0rcv", "l0plur")

l1_plot <- ggplot(inter_df, aes(x = lambda)) +
  geom_line(aes(y = L1RCV, group = case, colour = "IRV"), alpha = 0.05) +
  geom_line(aes(y = L1PLUR, group = case, colour = "Plurality") , alpha = 0.05) +
  geom_line(data = inter_df_agg, aes(y = l1rcv, colour = "IRV"), lwd = 2) +
  geom_line(data = inter_df_agg, aes(y = l1plur, colour = "Plurality"), lwd = 2) +
  theme_sv() +
  theme(legend.position = "bottom", legend.direction = "horizontal") + 
  xlim(0, 0.5) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_colour_manual(values = c(pal2[1], pal2[2]), labels = c("IRV", "Plurality"))
ggsave(here("../output/figures/cses_l1.pdf"), l1_plot, width = 5, height = 4, device = cairo_pdf)

l0_plot <- ggplot(inter_df, aes(x = lambda)) +
  geom_line(aes(y = L0RCV, group = case, colour = "IRV"), alpha = 0.05) +
  geom_line(aes(y = L0PLUR, group = case, colour = "Plurality") , alpha = 0.05) +
  geom_line(data = inter_df_agg, aes(y = l0rcv, colour = "IRV"), lwd = 2) +
  geom_line(data = inter_df_agg, aes(y = l0plur, colour = "Plurality"), lwd = 2) +
  theme_sv() +
  theme(legend.position = "bottom", legend.direction = "horizontal") + 
  xlim(0, 0.5) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_colour_manual(values = c(pal2[1], pal2[2]), labels = c("IRV", "Plurality"))
ggsave(here("../output/figures/cses_l0.pdf"), l0_plot, width = 5, height = 4, device = cairo_pdf)
