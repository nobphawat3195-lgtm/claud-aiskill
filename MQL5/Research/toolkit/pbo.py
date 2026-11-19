"""Overfitting checks for strategy selection.

pbo(M): Probability of Backtest Overfitting via Combinatorially Symmetric Cross-Validation
        (Bailey, Borwein, Lopez de Prado & Zhu, 2015). M is a T x N array: T periods (e.g. days or
        weeks) x N candidate configurations, each cell the return (or R) of that config in that period.
        For every split of the T periods into an in-sample half and an out-of-sample half, the config
        with the best in-sample Sharpe is located in the out-of-sample ranking. PBO is the share of
        splits where it lands in the bottom half. Below ~0.2 the selection is credible; above 0.5 the
        "best" config is no better than a random pick.

deflated_sharpe(r, n_trials): Deflated Sharpe Ratio (Bailey & Lopez de Prado, 2014). Probability that the
        true Sharpe of return series r is above zero after correcting for having tried n_trials configs,
        for skewness and for fat tails. Above 0.95 is significant.
"""
from itertools import combinations
import numpy as np
from scipy.stats import norm, skew, kurtosis


def _sharpe(x, axis=0):
    sd = x.std(axis=axis, ddof=1)
    return np.where(sd > 0, x.mean(axis=axis) / np.where(sd > 0, sd, 1), 0.0)


def pbo(M, S=10):
    M = np.asarray(M, float)
    T, N = M.shape
    S = S - S % 2
    blocks = np.array_split(np.arange(T), S)
    logits, oos_of_best = [], []
    for ins in combinations(range(S), S // 2):
        i_idx = np.concatenate([blocks[b] for b in ins])
        o_idx = np.concatenate([blocks[b] for b in range(S) if b not in ins])
        sr_is, sr_oos = _sharpe(M[i_idx]), _sharpe(M[o_idx])
        best = int(np.argmax(sr_is))
        rank = (sr_oos < sr_oos[best]).sum() + 1           # 1 = worst, N = best out of sample
        w = rank / (N + 1)
        logits.append(np.log(w / (1 - w)))
        oos_of_best.append(sr_oos[best])
    logits = np.array(logits)
    return dict(pbo=float((logits <= 0).mean()), splits=len(logits), median_logit=float(np.median(logits)),
                oos_sharpe_of_is_best_median=float(np.median(oos_of_best)))


def deflated_sharpe(r, n_trials, trial_sharpes=None):
    r = np.asarray(r, float)
    T = len(r)
    sr = r.mean() / r.std(ddof=1)
    var_sr = np.var(trial_sharpes, ddof=1) if trial_sharpes is not None and len(trial_sharpes) > 1 else 1.0 / T
    g = 0.5772156649
    sr0 = np.sqrt(var_sr) * ((1 - g) * norm.ppf(1 - 1.0 / n_trials) + g * norm.ppf(1 - 1.0 / (n_trials * np.e))) if n_trials > 1 else 0.0
    g3, g4 = skew(r), kurtosis(r, fisher=False)
    denom = np.sqrt(max(1 - g3 * sr + (g4 - 1) / 4 * sr ** 2, 1e-12))
    return dict(sharpe=float(sr), sr0=float(sr0), dsr=float(norm.cdf((sr - sr0) * np.sqrt(T - 1) / denom)))


if __name__ == '__main__':                              # self-test: pure noise must give PBO near 0.5
    rng = np.random.default_rng(0)
    print('noise ', pbo(rng.normal(0, 1, (500, 40))))
    M = rng.normal(0, 1, (500, 40)); M[:, 7] += 0.25    # one config with a real edge
    print('edge  ', pbo(M))
    print('DSR edge col', deflated_sharpe(M[:, 7], n_trials=40))
