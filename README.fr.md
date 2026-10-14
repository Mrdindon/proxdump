# proxdump — sauvegardes chiffrées de Proxmox VE vers un stockage en ligne

[English](README.md) | **Français** | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

`proxdump` sauvegarde les machines virtuelles et les conteneurs d'un nœud
**Proxmox VE** avec `vzdump`, **chiffre** les archives sur le serveur et les
envoie vers **Microsoft OneDrive**, **Google Drive**, **Dropbox**, tout
**stockage compatible S3** (Backblaze B2, Cloudflare R2, Wasabi, Amazon S3,
MinIO…) ou un **serveur SFTP**. Tout se pilote par des menus dans le
terminal ; il n'y a rien à apprendre de `rclone`.

![Démonstration de proxdump : sauvegarde d'un conteneur vers OneDrive, restauration sous un nouvel ID, menus de configuration et d'apparence](docs/demo.gif)

*Enregistré sur un vrai nœud ; les longs transferts sont accélérés. Interface montrée en anglais.*

## Points forts

- **Chiffré avant de quitter le serveur** : la destination ne reçoit que des
  données illisibles (XSalsa20-Poly1305, par `rclone crypt`). Les noms de
  fichiers restent lisibles et portent le suffixe `.encrypted`.
- **Cinq types de destination**, plusieurs à la fois : l'archive est créée
  une seule fois, puis envoyée vers chaque destination choisie.
- **Vérifié** : après chaque envoi, la copie distante est comparée à
  l'archive locale par somme de contrôle.
- **Rétention** : nombre de versions conservées, global ou par invité,
  appliqué après chaque sauvegarde.
- **Restauration** sous l'ID d'origine, sous un nouvel ID, ou simple
  téléchargement de l'archive déchiffrée. Les archives sont des archives
  `vzdump` standard : elles se restaurent aussi sans cet outil.
- **Planification** : plusieurs planifications (quotidiennes,
  hebdomadaires, mensuelles, annuelles ou manuelles ; tous les invités ou une
  sélection ; une ou plusieurs destinations), chacune pouvant être exécutée
  sur-le-champ, et dont les invités, la fréquence et l'heure se modifient
  ensuite.
- **Connexions guidées** : autorisation pas à pas pour OneDrive, Google
  Drive et Dropbox sur un serveur sans navigateur web ; formulaires simples
  pour S3 et SFTP.
- **Deux interfaces** : une interface native avec thèmes de couleurs, souris
  et fenêtre de progression animée, ou les dialogues `whiptail` classiques.
- **Mises à jour** : les menus indiquent s'il s'agit de la dernière version
  et proposent d'installer la nouvelle ; `proxdump update` fait de même en
  ligne de commande.
- **Six langues** : anglais, français, espagnol, allemand, chinois
  (simplifié) et russe, pour l'interface et le journal.
- **Empreinte réduite** : un script bash, `rclone`, `jq` et ce qu'un nœud
  Proxmox VE fournit déjà.

## Fonctionnement

```
invité (VM/CT)                dossier de transit local                    destination(s)
┌─────────────┐   vzdump    ┌───────────────────────────┐   rclone   ┌──────────────────────┐
│ 100 web     │ ──────────> │ vzdump-qemu-100-….vma.zst │ ─────────> │ pve-backups/<node>/  │
└─────────────┘             │ en clair, puis supprimé   │   crypt    │ ….vma.zst.encrypted  │
                            └───────────────────────────┘            └──────────────────────┘
```

Pour chaque invité : `vzdump` crée l'archive dans un dossier temporaire,
`rclone` la chiffre et l'envoie, la copie est vérifiée, la rétention est
appliquée, puis le dossier temporaire est supprimé. C'est `vzdump` qui décide
du contenu de l'archive : le réglage « Sauvegarde » de chaque disque dans
Proxmox VE est donc respecté.

## Destinations

| Destination | Connexion | À savoir |
|---|---|---|
| Microsoft OneDrive | Autorisation dans un navigateur, jeton collé sur le serveur | 250 Go par fichier |
| Google Drive | Idem, avec un client OAuth à vous (gratuit) | 750 Go envoyés par jour |
| Dropbox | Autorisation dans un navigateur, jeton collé sur le serveur | 350 Go par fichier |
| Stockage compatible S3 | Clé d'accès, secret et bucket | Backblaze B2, Cloudflare R2, Wasabi, Amazon S3, Hetzner, OVHcloud, Scaleway, MinIO… |
| Serveur SFTP | Clé SSH générée par l'outil, ou mot de passe | NAS, autre serveur, stockage loué |

## Prérequis

- un nœud Proxmox VE (développé et testé sur PVE 9 / Debian 13), accès root ;
- au moins une destination disposant d'assez d'espace ;
- un dossier local pouvant contenir temporairement la plus grosse archive ;
- pour OneDrive, Google Drive et Dropbox : un ordinateur avec un navigateur
  web et [rclone](https://rclone.org/downloads/), une seule fois, pour
  l'autorisation.

## Installation

```bash
git clone https://github.com/Mrdindon/proxdump.git
cd proxdump
./install.sh
```

`install.sh` installe ce qui manque (`rclone` depuis son paquet officiel,
`jq`, `whiptail`, `curl`) et copie l'outil dans `/usr/local/bin/proxdump`.
Pour mettre à jour : `git pull && ./install.sh`. Pour désinstaller :
`./install.sh --uninstall` (la configuration est conservée).

Sur un nœud sans git, téléchargez le paquet `.deb` depuis les
[versions publiées](https://github.com/Mrdindon/proxdump/releases) et installez-le
avec `apt install ./proxdump_*.deb`.

## Premiers pas

Lancez `proxdump` en root, puis dans **Configuration** :

1. connectez au moins une destination ;
2. définissez la phrase secrète de chiffrement, et **notez-la hors du
   serveur** : sans elle, les sauvegardes sont irrécupérables ;
3. vérifiez le dossier de transit local et les options de sauvegarde.

Ensuite, **Sauvegarder des machines virtuelles et des conteneurs** pour une
première sauvegarde, et **Planification automatique** pour les suivantes.

## Ligne de commande

```bash
proxdump                                  # les menus
proxdump backup --all                     # tous les invités, toutes les destinations
proxdump backup --to s3,onedrive 100 101  # invités et destinations indiqués
proxdump list                             # sauvegardes stockées
proxdump prune                            # appliquer la rétention
proxdump update                           # installer la dernière version
```

## Documentation

La documentation détaillée est en anglais :

- [Connecting the destinations](docs/CONNECTIONS.md) — OneDrive, Google
  Drive, Dropbox, S3, SFTP, durée de vie des jetons d'accès ;
- [Using proxdump](docs/USAGE.md) — langue et apparence, chiffrement,
  sauvegarde, gestion, restauration, planification et ligne de commande ;
- [Encryption](docs/ENCRYPTION.md) — algorithmes, ce qui reste visible sur
  la destination, où sont conservés les secrets ;
- [Disaster recovery](docs/RECOVERY.md) — restaurer sur un nouveau serveur,
  avec ou sans cet outil ;
- [Reference](docs/REFERENCE.md) — fichiers et sécurité, dépannage, limites
  connues ;
- [Development](docs/DEVELOPMENT.md) — tester sans compte réel, traductions.

## Limites

- Un nœud à la fois : l'outil sauvegarde les invités du nœud sur lequel il
  s'exécute.
- Sauvegardes complètes uniquement (ni incrémentiel, ni déduplication).
- Il faut de l'espace local pour l'archive compressée, à la sauvegarde comme
  à la restauration.
- Les traductions n'ont pas été relues par des locuteurs natifs : les
  corrections sont bienvenues.

## Comment il a été fait

proxdump a été écrit avec [Claude Code](https://claude.com/claude-code),
l'agent de programmation d'Anthropic, dirigé et relu par l'auteur, et testé
sur un vrai nœud Proxmox VE (voir
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)). Les notes de conception et les
leçons apprises sont dans la même page ; [AGENTS.md](AGENTS.md) est le guide
donné aux agents de code qui y travaillent.

## Licence

[AGPL-3.0-or-later](LICENSE).
