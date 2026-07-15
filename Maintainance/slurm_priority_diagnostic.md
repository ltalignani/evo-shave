# Diagnostic de priorité SLURM — Guide opérationnel

Ce guide explique comment diagnostiquer pourquoi des jobs SLURM restent en attente
(`PENDING`) et comment interpréter les résultats pour décider de la marche à suivre.

---

## 1. Vérifier l'état et la raison d'attente

```bash
squeue --me --format="%i %j %T %R %Q %p" | sort -k5 -n
```

| Colonne | Signification |
|---|---|
| `%i` | Job ID |
| `%j` | Nom du job |
| `%T` | État (`PENDING`, `RUNNING`, `FAILED`…) |
| `%R` | **Raison** (colonne clé) |
| `%Q` | Priorité numérique globale |
| `%p` | Priorité normalisée (0–1) |

### Raisons fréquentes dans la colonne `%R`

| Raison | Signification | Action |
|---|---|---|
| `Priority` | D'autres jobs ont une priorité plus haute | Attendre, changer de compte |
| `Resources` | Pas assez de CPUs/mémoire disponibles | Attendre la libération de nœuds |
| `QOSMaxJobsPerUser` | Limite de jobs simultanés atteinte | Réduire `--jobs` dans Snakemake |
| `AssocGrpCPURunMinutes` | Quota CPU-minutes du compte épuisé | Contacter l'admin |
| `Dependency` | Le job attend un autre job | Normal (Snakemake gère ça) |

---

## 2. Décomposer la priorité d'un job

```bash
sprio -u <LOGIN> -l
```

Exemple de sortie :
```
JOBID  PARTITION  USER      ACCOUNT   PRIORITY    AGE  FAIRSHARE  JOBSIZE  PARTITION  QOS
12345  long       ltaligna  invalbo   10267089  122609     116243    28237   10000000    0
```

### Interprétation des composantes

| Composante | Rôle | Comment l'améliorer |
|---|---|---|
| `PARTITION` | Bonus fixe selon la partition (`long` = 10 M) | Choisir la partition avec le bonus le plus élevé |
| `AGE` | Augmente avec le temps d'attente | Augmente automatiquement (~12h pour compenser un FAIRSHARE déprimé) |
| `FAIRSHARE` | **Baisse si tu as beaucoup consommé** | Attendre (demi-vie 7–14 jours) ou changer de compte |
| `JOBSIZE` | Bonus proportionnel à la taille du job | Peu actionnable |
| `QOS` | Bonus fixé par l'admin | Non actionnable sans intervention admin |

> **Règle pratique :** si `FAIRSHARE` ≈ `AGE`, un job en attente depuis ~12h supplémentaires
> rattrapera son retard naturellement. Si `FAIRSHARE` ≪ `AGE`, le problème est structurel
> (consommation massive récente) et nécessite plusieurs jours de récupération.

---

## 3. Analyser le FairShare avec `sshare`

```bash
sshare -u <LOGIN> -l > sshare_results.txt
```

Puis chercher les lignes pertinentes :

```bash
grep -i "<LOGIN>\|<COMPTE>" sshare_results.txt
```

### Colonnes clés de `sshare`

| Colonne | Signification |
|---|---|
| `RawShares` | Quota alloué au compte/utilisateur |
| `RawUsage` | Consommation brute (CPU-secondes) depuis la dernière réinitialisation |
| `EffectvUsage` | Part de la consommation totale du compte attribuée à cet utilisateur (0–1) |
| `FairShare` | Score FairShare brut |
| **`LevelFS`** | **FairShare normalisé — indicateur clé** |

### Interpréter `LevelFS`

| Valeur `LevelFS` | Situation | Priorité attendue |
|---|---|---|
| `> 1.0` | Sous-consommation — bonus de priorité | Élevée |
| `≈ 1.0` | Consommation équilibrée | Normale |
| `0.5 – 1.0` | Légère surconsommation | Réduite |
| `0.1 – 0.5` | Forte surconsommation | Faible |
| `< 0.1` | Très forte surconsommation (×10 la quote-part) | Très faible |
| `inf` | Aucune consommation récente | Maximale |

### Hiérarchie des pénalités

SLURM applique le FairShare à deux niveaux qui se **multiplient** :

```
Priorité ∝ LevelFS(compte) × LevelFS(utilisateur dans le compte)
```

Exemple réel (evo-shave) :
```
invalbo (compte)          LevelFS = 0.095   ← pénalité niveau cluster
  ltalignani (dans invalbo)  LevelFS = 0.167   ← pénalité niveau utilisateur
```
Résultat : priorité effective ≈ 0.095 × 0.167 ≈ **×60 en dessous** d'un utilisateur sans historique.

---

## 4. Comparer avec les autres utilisateurs du cluster

```bash
# Voir les LevelFS de tous les comptes (trier par LevelFS croissant = plus pénalisés en premier)
grep -v "^-" sshare_results.txt | awk '{print $1, $NF}' | sort -k2 -n | head -30
```

```bash
# Voir tous les comptes auxquels tu appartiens et leur LevelFS
grep "<LOGIN>" sshare_results.txt | awk '{printf "%-40s LevelFS=%-10s EffectvUsage=%s\n", $1, $NF, $7}'
```

---

## 5. Choisir le meilleur compte pour relancer

Si tu as accès à plusieurs comptes, compare leurs `LevelFS` :

```bash
grep "<LOGIN>" sshare_results.txt | awk '{print $1, $9, $10}' | column -t
# Colonnes : Compte, FairShare, LevelFS
```

Utiliser le compte avec le **`LevelFS` le plus élevé** pour maximiser la priorité.

Pour changer de compte dans evo-shave, modifier `profile/config.yaml` :
```yaml
default-resources:
  slurm_account: "nouveau_compte"   # remplacer invalbo par le compte choisi
```

---

## 6. Estimer le délai de récupération

Le FairShare décroît avec une demi-vie configurable par l'admin (typiquement 7–14 jours).
Pour estimer :

```bash
# Voir la configuration FairShare du cluster
scontrol show config | grep -i "priority\|fairshare\|decay"
```

| Paramètre | Signification |
|---|---|
| `PriorityDecayHalfLife` | Temps pour que la consommation soit réduite de moitié |
| `PriorityUsageResetPeriod` | Réinitialisation complète périodique (si configurée) |
| `PriorityFavorSmall` | Si `YES`, les petits jobs sont favorisés |

> **Exemple :** avec une demi-vie de 7 jours et `LevelFS = 0.1`, il faut ~23 jours pour
> atteindre `LevelFS = 0.9` (4 demi-vies × 7 jours), mais seulement ~3 jours pour
> passer de 0.1 à 0.4.

---

## 7. Demander un boost de priorité à l'admin

Si le run est urgent et qu'attendre n'est pas envisageable :

```bash
# Afficher les informations à communiquer à l'admin
squeue --me --format="%i %j %T %R %Q" | head -5
sshare -u <LOGIN> -l | grep "<COMPTE>"
```

L'admin peut exécuter :
```bash
# Modifier manuellement la priorité (admin seulement)
scontrol update job <JOBID> Priority=<VALEUR>
# ou via le flag Nice (valeur négative = priorité plus haute)
scontrol update job <JOBID> Nice=-100
```

---

## Récapitulatif décisionnel

```
Jobs en PENDING (Priority) ?
│
├─ sprio → FAIRSHARE ≈ AGE ?
│   ├─ OUI → attendre ~12h, la priorité se rééquilibre seule
│   └─ NON (FAIRSHARE ≪ AGE) → problème FairShare structurel
│       │
│       └─ sshare → LevelFS du compte < 0.2 ?
│           ├─ OUI → double pénalité compte + utilisateur
│           │   ├─ Changer de compte (si autre compte avec LevelFS > 0.5)
│           │   ├─ Contacter l'admin pour boost ponctuel
│           │   └─ Attendre 3–7 jours
│           └─ NON → pénalité utilisateur seulement → attendre 1–3 jours
│
└─ Jobs en PENDING (Resources) ?
    └─ sinfo -p <PARTITION> → nœuds disponibles ?
        ├─ OUI → problème de ressources demandées (mem/cpu trop élevés)
        └─ NON → cluster saturé, attendre
```
