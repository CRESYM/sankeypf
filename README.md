# 🚀 Guide de démarrage rapide – Projet Julia

## 1️⃣ Installer Julia
1. Rendez-vous sur le site officiel : [https://julialang.org/downloads/](https://julialang.org/downloads/)  
2. Téléchargez la version correspondant à votre système (Windows / macOS / Linux).  
3. Installez Julia en suivant les instructions par défaut.  
   > 💡 Sous Windows, vous pouvez cocher **« Ajouter Julia au PATH »** pour plus de commodité.

---

## 2️⃣ Extraire le projet
1. Décompressez le fichier `.zip` que vous avez reçu (par exemple sur votre Bureau).  
2. Vous devriez obtenir une structure comme ceci :
   ```
   MonProjet/
   ├── Project.toml
   ├── src/
   └── demo/
       └── demo.jl
   ```

---

## 3️⃣ Activer et instancier l’environnement

### 🔹 Option 1 — Depuis la console Julia
1. Ouvrez **Julia**.  
2. Déplacez-vous dans le dossier du projet :
   ```julia
   cd("C:/Users/VotreNom/Bureau/MonProjet")
   ```
3. Entrez dans le gestionnaire de paquets (tapez `]` dans le REPL), puis :
   ```julia
   activate .
   instantiate
   ```
   Cela active l’environnement du projet et installe toutes les dépendances.

---

### 🔹 Option 2 — Depuis VS Code
1. Ouvrez **Visual Studio Code**.  
2. Installez l’extension **Julia** si ce n’est pas déjà fait.  
3. Ouvrez le dossier du projet (**Fichier → Ouvrir le dossier...**).  
4. Le terminal Julia intégré détectera automatiquement l’environnement,  
   **mais il faut encore l’instancier manuellement** :
   ```julia
   import Pkg
   Pkg.instantiate()
   ```
   ➜ Cela installe toutes les dépendances définies dans `Project.toml`.

---

## 4️⃣ Lancer la démo
Une fois l’environnement prêt, lancez simplement :
```julia
include("demo/demo.jl")
```

✅ Le script de démonstration s’exécutera avec toutes les bibliothèques déjà installées.

---

## 5️⃣ En cas de problème

- **`UndefVarError: Pkg not defined`**  
  → Tapez d’abord `using Pkg` avant `Pkg.instantiate()`.

- **Erreur de chemin (`cd`)**  
  → Vérifiez que le dossier entre guillemets correspond bien à l’endroit où vous avez extrait le projet.

- **Problème de dépendances**  
  → Essayez de relancer Julia et de refaire :
  ```julia
  import Pkg
  Pkg.activate(".")
  Pkg.instantiate()
  ```

---

🧠 *Julia crée un environnement isolé pour chaque projet.  
Une fois instancié, vous n’aurez plus à refaire cette étape sauf si de nouvelles dépendances sont ajoutées.*
