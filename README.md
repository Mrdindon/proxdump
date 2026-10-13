# onedrivepbs

Sauvegarde **chiffrée** des machines virtuelles et conteneurs d'un nœud
**Proxmox VE** vers **Microsoft OneDrive**, pilotée par des menus `whiptail`.

- sauvegarde de VM (QEMU) et de conteneurs (LXC) avec `vzdump` ;
- chiffrement côté serveur *avant* l'envoi (contenu **et** noms de fichiers) ;
- identifiants OneDrive et phrase secrète mémorisés localement pour les fois suivantes ;
- gestion des sauvegardes déjà présentes sur OneDrive : liste, suppression,
  nombre de versions conservées (global ou par invité) ;
- restauration sous l'ID d'origine, sous un nouvel ID, ou simple téléchargement ;
- planification par cron et sous-commandes non interactives.

```
┌──────────────────────── onedrivepbs 1.0.0 ────────────────────────┐
│ Sauvegarde chiffrée Proxmox VE -> OneDrive   (nœud : pve)         │
│                                                                   │
│        1  Sauvegarder des VM / conteneurs                         │
│        2  Restaurer une sauvegarde                                │
│        3  Gérer les sauvegardes sur OneDrive                      │
│        4  Planification automatique                               │
│        5  Configuration                                           │
│        6  Journal                                                 │
│        Q  Quitter                                                 │
└───────────────────────────────────────────────────────────────────┘
```

## Sommaire

1. [Fonctionnement](#fonctionnement)
2. [Prérequis](#prérequis)
3. [Installation](#installation)
4. [Configuration initiale](#configuration-initiale)
5. [Sauvegarder](#sauvegarder)
6. [Gérer les sauvegardes sur OneDrive](#gérer-les-sauvegardes-sur-onedrive)
7. [Restaurer](#restaurer)
8. [Reprise après sinistre](#reprise-après-sinistre-serveur-perdu)
9. [Planification et ligne de commande](#planification-et-ligne-de-commande)
10. [Fichiers et sécurité](#fichiers-et-sécurité)
11. [Dépannage](#dépannage)
12. [Limites connues](#limites-connues)
13. [Développement et tests](#développement-et-tests)

## Fonctionnement

```
 invité (VM/CT)                dossier temporaire local            OneDrive
┌─────────────┐   vzdump     ┌─────────────────────────┐  rclone  ┌──────────────────────┐
│ 100 web     │ ───────────▶ │ vzdump-qemu-100-….vma.zst│ ──────▶ │ pve-backups/<nœud>/  │
└─────────────┘              │ (en clair, effacé après) │  crypt  │   <noms chiffrés>    │
                             └─────────────────────────┘          └──────────────────────┘
```

Pour chaque invité sélectionné :

1. `vzdump` crée l'archive (et son journal) dans un sous-dossier temporaire ;
2. `rclone` l'envoie à travers un *remote* `crypt` : le fichier est chiffré
   localement (XSalsa20-Poly1305, clé dérivée de la phrase secrète par scrypt),
   OneDrive ne reçoit que des données et des noms illisibles ;
3. `rclone cryptcheck` compare les sommes de contrôle locales et distantes ;
4. le sous-dossier temporaire est effacé ;
5. la rétention est appliquée à cet invité (les versions les plus anciennes
   au-delà du nombre configuré sont supprimées).

Une fois déchiffrée, l'arborescence distante ressemble à ceci :

```
pve-backups/<nœud>/
├── 100_web/
│   ├── vzdump-qemu-100-2026_10_12-02_00_03.vma.zst
│   └── vzdump-qemu-100-2026_10_12-02_00_03.log
└── 101_dns/
    ├── vzdump-lxc-101-2026_10_12-02_04_41.tar.zst
    └── vzdump-lxc-101-2026_10_12-02_04_41.log
```

Les archives sont des archives `vzdump` standard : une fois téléchargées et
déchiffrées, elles se restaurent aussi avec `qmrestore` / `pct restore` ou
l'interface web de Proxmox, sans cet outil.

## Prérequis

- un nœud Proxmox VE (développé et testé sur PVE 9 / Debian 13), accès root ;
- un compte Microsoft OneDrive (personnel ou professionnel) avec assez d'espace ;
- un dossier local pouvant contenir temporairement la plus grosse archive ;
- pour la première connexion : un ordinateur avec un navigateur web et
  [rclone](https://rclone.org/downloads/) (Windows, macOS ou Linux).

Dépendances installées par `install.sh` si elles manquent : `rclone` (paquet
officiel, celui de Debian étant trop ancien pour OneDrive), `jq`, `whiptail`, `curl`.

## Installation

```bash
git clone https://github.com/Mrdindon/onedrivepbs.git
cd onedrivepbs
./install.sh
```

Le script copie l'outil dans `/usr/local/bin/onedrivepbs` et crée
`/etc/onedrivepbs` (mode 700). Pour mettre à jour : `git pull && ./install.sh`.
Pour retirer : `./install.sh --uninstall` (la configuration est conservée).

## Configuration initiale

Lancez `onedrivepbs` en root et ouvrez **Configuration**. Trois étapes.

### 1. Connexion OneDrive

Un serveur Proxmox n'a pas de navigateur : l'autorisation Microsoft se fait
donc depuis un autre ordinateur, une seule fois.

1. Dans le menu : **Configuration → Connexion OneDrive → Assistant guidé**.
2. Sur votre ordinateur (avec navigateur et rclone), exécutez :
   ```
   rclone authorize "onedrive"
   ```
3. Le navigateur s'ouvre : connectez-vous au compte Microsoft et acceptez
   l'accès demandé par rclone.
4. rclone affiche un long bloc de texte entre `--->` et `<---End paste`.
   Copiez-le et collez-le dans l'assistant : les coupures de ligne ajoutées
   par le terminal et les flèches copiées par mégarde sont ignorées, et un
   jeton incomplet est redemandé. Si le collage pose problème, enregistrez ce
   bloc dans un fichier sur le serveur et donnez le chemin du fichier à la
   place.
5. L'assistant pose ensuite les questions de rclone : type de compte
   (choisissez `onedrive` pour un compte personnel ou professionnel), puis
   confirmation du lecteur. Les lecteurs techniques de Microsoft sont
   écartés ; le choix n'est proposé que s'il reste plusieurs lecteurs.
6. Un test de connexion affiche l'espace total et libre du compte.

Le jeton obtenu est enregistré dans `/etc/onedrivepbs/rclone.conf` ; rclone le
renouvelle automatiquement. Il ne faudra refaire cette étape que si l'accès est
révoqué ou si le jeton reste inutilisé plus de 90 jours.

Cas particuliers (bibliothèque SharePoint, application Azure propre…) : utilisez
**Configuration rclone manuelle** et créez un remote nommé `onedrive`.

### 2. Chiffrement

**Configuration → Chiffrement** propose de générer une phrase secrète aléatoire
(recommandé) ou de saisir la vôtre.

> **Notez cette phrase hors du serveur** (gestionnaire de mots de passe,
> papier). Elle est indispensable pour restaurer si ce serveur est perdu.
> Sans elle, les sauvegardes sont définitivement illisibles — personne, pas
> même Microsoft, ne peut les déchiffrer.

Le même menu permet de réafficher la phrase plus tard, ou de la changer.
Attention : les sauvegardes existantes restent chiffrées avec l'ancienne phrase.

### 3. Dossiers et options

| Réglage | Défaut | Rôle |
|---|---|---|
| Dossier OneDrive | `pve-backups/<nœud>` | Emplacement des sauvegardes dans OneDrive |
| Dossier temporaire local | `/var/lib/vz/dump` | Où `vzdump` écrit l'archive avant l'envoi. Choisissez un stockage avec assez d'espace libre |
| Mode vzdump | `snapshot` | `snapshot` (sans interruption), `suspend` ou `stop` |
| Compression | `zstd` | `zstd`, `gzip`, `lzo` ou aucune |
| Limite de débit | aucune | Par ex. `10M` pour ne pas saturer la connexion |
| Vérification après envoi | oui | Comparaison des sommes de contrôle |

## Sauvegarder

Menu **1 – Sauvegarder des VM / conteneurs** : cochez les invités (barre
d'espace), validez. La progression de `vzdump` puis de l'envoi s'affiche dans
le terminal. Un échec sur un invité n'empêche pas les suivants ; le résumé
final indique le nombre de réussites.

Conseil : lancez l'outil dans `tmux` ou `screen` pour les grosses sauvegardes,
afin qu'une coupure SSH n'interrompe pas l'envoi.

## Gérer les sauvegardes sur OneDrive

Menu **3 – Gérer les sauvegardes sur OneDrive** :

| Entrée | Effet |
|---|---|
| Lister les sauvegardes | ID, type, nom, date et taille de chaque sauvegarde, et total |
| Supprimer des sauvegardes | Suppression de celles que vous cochez (avec confirmation) |
| Versions conservées (rétention) | Nombre de versions gardées par invité : valeur par défaut, et valeur propre à un invité |
| Appliquer la rétention maintenant | Purge immédiate selon les réglages |
| Espace utilisé sur OneDrive | Quota du compte |

Règles de rétention :

- la valeur par défaut est **3** versions par invité ;
- une valeur propre à un invité remplace la valeur par défaut pour cet invité ;
- **0** signifie « tout conserver » ;
- la rétention s'applique automatiquement après chaque sauvegarde réussie de
  l'invité concerné, jamais après un échec ;
- les fichiers supprimés passent par la corbeille OneDrive (toujours chiffrés)
  et continuent d'occuper le quota jusqu'à ce qu'elle soit vidée.

## Restaurer

Menu **2 – Restaurer une sauvegarde** : choisissez la sauvegarde, puis :

| Choix | Effet |
|---|---|
| Restaurer sous l'ID d'origine | Recrée l'invité. S'il existe déjà, il est **écrasé** après confirmation (il doit être arrêté) |
| Restaurer sous un nouvel ID | Crée une copie ; l'outil propose le prochain ID libre et de nouvelles adresses MAC |
| Télécharger seulement | Dépose l'archive déchiffrée dans le dossier indiqué, sans restaurer |

L'outil demande ensuite le stockage de destination des disques, télécharge et
déchiffre l'archive dans le dossier temporaire, lance `qmrestore` (VM) ou
`pct restore` (conteneur), puis efface l'archive temporaire.

Après une restauration sous un nouvel ID, pensez à vérifier l'adresse IP et le
nom d'hôte avant de démarrer la copie si l'original tourne encore.

## Reprise après sinistre (serveur perdu)

Il vous faut : l'accès au compte OneDrive et la **phrase secrète**.

1. Installez Proxmox VE sur le nouveau serveur, puis onedrivepbs (`./install.sh`).
2. **Configuration → Connexion OneDrive** : refaites l'autorisation.
3. **Configuration → Dossier OneDrive** : indiquez le dossier de l'ancien
   serveur, par ex. `pve-backups/ancien-nom` (le défaut utilise le nom du
   nouveau nœud).
4. **Configuration → Chiffrement → Saisir ma propre phrase** : entrez la phrase
   secrète d'origine.
5. **Gérer → Lister** : les sauvegardes doivent apparaître. Si la liste est
   vide alors que le dossier contient des fichiers, la phrase ou le dossier
   est incorrect.
6. **Restaurer** chaque invité.

Sans cet outil, avec n'importe quel rclone, la même chose à la main :

```ini
# rclone.conf
[onedrive]
type = onedrive
# … créé par « rclone config »

[onedrive-crypt]
type = crypt
remote = onedrive:pve-backups/<nœud>
password = <résultat de : rclone obscure 'votre phrase secrète'>
filename_encryption = standard
directory_name_encryption = true
```

```bash
rclone lsf -R onedrive-crypt:
rclone copy onedrive-crypt:100_web/vzdump-qemu-100-….vma.zst /var/lib/vz/dump/
qmrestore /var/lib/vz/dump/vzdump-qemu-100-….vma.zst 100 --storage local-lvm
```

**Testez une restauration** (sous un nouvel ID) de temps en temps : une
sauvegarde jamais restaurée n'est qu'un espoir.

## Planification et ligne de commande

Menu **4 – Planification automatique** : quotidienne ou hebdomadaire, heure de
lancement, tous les invités ou une sélection. L'outil écrit
`/etc/cron.d/onedrivepbs` ; « Désactiver » le supprime.

Sous-commandes utilisables dans vos propres scripts :

```
onedrivepbs backup --all       # tous les invités du nœud
onedrivepbs backup 100 101     # invités précis
onedrivepbs list               # sauvegardes présentes sur OneDrive
onedrivepbs prune              # applique la rétention
```

`backup` renvoie le nombre d'échecs comme code de retour (0 = tout a réussi).
Un verrou empêche deux opérations simultanées.

## Fichiers et sécurité

| Fichier | Contenu | Droits |
|---|---|---|
| `/usr/local/bin/onedrivepbs` | L'outil | 755 |
| `/etc/onedrivepbs/rclone.conf` | **Jeton OneDrive et phrase secrète** | 600, dossier 700 |
| `/etc/onedrivepbs/config` | Réglages (aucun secret) | 600 |
| `/etc/cron.d/onedrivepbs` | Planification | 644 |
| `/var/log/onedrivepbs.log` | Journal des opérations | — |

À savoir :

- Dans `rclone.conf`, la phrase secrète est seulement *obscurcie* par rclone,
  pas chiffrée : quiconque lit ce fichier peut déchiffrer les sauvegardes et
  accéder au OneDrive. Il n'est lisible que par root ; ne le copiez pas
  ailleurs sans protection et ne le versionnez jamais.
- Le chiffrement protège vos données vis-à-vis de OneDrive et de quiconque
  accéderait au compte. Il ne protège pas contre quelqu'un qui est root sur le
  serveur Proxmox.
- Pendant une sauvegarde ou une restauration, l'archive existe **en clair**
  dans le dossier temporaire local ; elle est effacée dès la fin de
  l'opération, y compris en cas d'erreur ou d'interruption.
- La taille des fichiers et la date d'envoi restent visibles côté OneDrive.
- Ce dépôt ne contient ni identifiant, ni jeton, ni phrase secrète : tout cela
  vit uniquement dans `/etc/onedrivepbs`, et le `.gitignore` exclut ces fichiers.

## Dépannage

| Symptôme | Piste |
|---|---|
| « OneDrive et/ou le chiffrement ne sont pas encore configurés » | Terminer les étapes 1 et 2 de la configuration |
| Le jeton collé est refusé | Utiliser la même version de rclone des deux côtés ; coller sur une seule ligne, ou passer par un fichier |
| Échec du test de connexion après quelques mois | Jeton expiré ou révoqué : refaire **Connexion OneDrive** |
| `vzdump` échoue faute de place | Changer le **dossier temporaire local** pour un stockage plus grand |
| Envoi très lent ou erreurs 429 | Microsoft limite le débit ; rclone réessaie seul. Éviter les heures de pointe |
| Liste vide alors que OneDrive contient des fichiers | Mauvaise phrase secrète ou mauvais **dossier OneDrive** |
| « Une autre opération onedrivepbs est déjà en cours » | Attendre la fin de la sauvegarde planifiée, ou vérifier avec `ps aux \| grep onedrivepbs` |
| La restauration sous l'ID d'origine échoue | L'invité existant doit être arrêté et non verrouillé |

Le détail de chaque opération (sorties de `vzdump` et de `rclone`) est dans
`/var/log/onedrivepbs.log`, consultable aussi par le menu **Journal**.

## Limites connues

- Un seul nœud à la fois : l'outil sauvegarde les invités du nœud où il tourne.
- Sauvegardes complètes uniquement (pas d'incrémental ni de déduplication) :
  chaque version occupe sa taille compressée entière sur OneDrive.
- Taille maximale d'un fichier sur OneDrive : 250 Go par archive.
- Il faut localement l'espace de l'archive compressée, à la sauvegarde comme
  à la restauration.
- La restauration n'existe que dans les menus (pas de sous-commande).

## Développement et tests

Le script passe `shellcheck` sans avertissement. Pour essayer l'outil sans
toucher à la configuration réelle ni à un vrai compte OneDrive, on peut
rediriger ses fichiers et utiliser un dossier local comme faux OneDrive :

```bash
export ONEDRIVEPBS_CONF_DIR=/tmp/odp/conf ONEDRIVEPBS_LOG=/tmp/odp/log \
       ONEDRIVEPBS_LOCK=/tmp/odp/lock ONEDRIVEPBS_CRON=/tmp/odp/cron
mkdir -p /tmp/odp/conf /tmp/odp/faux-onedrive
printf '[onedrive]\ntype = alias\nremote = /tmp/odp/faux-onedrive\n' > /tmp/odp/conf/rclone.conf
./onedrivepbs      # puis Configuration → Chiffrement, et une sauvegarde d'essai
```

## Licence

MIT — voir [LICENSE](LICENSE).
