# Unusual dog gun breeds

This is a curated collection of 20 breeds with distinctive silhouettes, coats,
faces or proportions. “Strange” is a subjective art direction; this collection
does not claim an authoritative ranking. These are original low-poly models,
with stylized proportions based on the American Kennel Club breed references.

| Breed | Features emphasized | Reference |
| --- | --- | --- |
| Xoloitzcuintli | Hairless slate skin, lean body and tall ears | [AKC](https://www.akc.org/dog-breeds/xoloitzcuintli/) |
| Chinese Crested | Crest, spotted skin, furry socks and tail plume | [AKC](https://www.akc.org/dog-breeds/chinese-crested/) |
| Peruvian Inca Orchid | Hairless sighthound silhouette and forehead tuft | [AKC](https://www.akc.org/dog-breeds/peruvian-inca-orchid/) |
| American Hairless Terrier | Compact hairless terrier and upright ears | [AKC](https://www.akc.org/dog-breeds/american-hairless-terrier/) |
| Komondor | Large ivory body and long coat cords | [AKC](https://www.akc.org/dog-breeds/komondor/) |
| Puli | Compact charcoal dog, coat cords and curled tail | [AKC](https://www.akc.org/dog-breeds/puli/) |
| Bergamasco Shepherd | Broad gray dog with flat overlapping coat flocks | [AKC](https://www.akc.org/dog-breeds/bergamasco-sheepdog/) |
| Bedlington Terrier | Lamb-like head, topknot, arched back and tasselled ears | [AKC](https://www.akc.org/dog-breeds/bedlington-terrier/) |
| Bull Terrier | Egg-shaped head and small upright ears | [AKC](https://www.akc.org/dog-breeds/bull-terrier/) |
| Neapolitan Mastiff | Heavy frame, face wrinkles, drooping jowls and dewlap | [AKC](https://www.akc.org/dog-breeds/neapolitan-mastiff/) |
| Shar-Pei | Skin folds, tiny ears and curled tail | [AKC](https://www.akc.org/dog-breeds/chinese-shar-pei/) |
| Brussels Griffon | Short face, beard and expressive eyebrows | [AKC](https://www.akc.org/dog-breeds/brussels-griffon/) |
| Affenpinscher | Monkey-like face and shaggy whiskers | [AKC](https://www.akc.org/dog-breeds/affenpinscher/) |
| Borzoi | Very long narrow muzzle and tall feathered sighthound | [AKC](https://www.akc.org/dog-breeds/borzoi/) |
| Afghan Hound | Long silky skirt, hanging ears and topknot | [AKC](https://www.akc.org/dog-breeds/afghan-hound/) |
| Saluki | Slender frame, long legs and feathered ears | [AKC](https://www.akc.org/dog-breeds/saluki/) |
| Azawakh | Fine-boned tall sighthound, white socks and chest blaze | [AKC](https://www.akc.org/dog-breeds/azawakh/) |
| Norwegian Lundehund | Spitz ears, curled tail and six toes | [AKC](https://www.akc.org/dog-breeds/norwegian-lundehund/) |
| Otterhound | Large shaggy hound, broad beard and long drop ears | [AKC](https://www.akc.org/dog-breeds/otterhound/) |
| Dandie Dinmont Terrier | Long low body, short legs and puffy topknot | [AKC](https://www.akc.org/dog-breeds/dandie-dinmont-terrier/) |

References consulted October 4, 2026. Breed features guide the art only; damage,
ammo, shot intervals and flavors are original game design values.

`build_dogs.py` produces 20 GLBs, `unusual-dog-guns.blend`, a labelled contact
sheet and mesh triangle counts in `models.json`. Each GLB faces Godot -Z,
starts at ground level and exports `HeadRoot`, `MouthAnchor`, `GlassesAnchor`,
and `CollarAnchor`. The head remains separate for stacking spring collars.

`DogBreeds.create_stats(run_rng, breed_id, rarity)` selects breed and elemental
type independently. Every breed has a 25% chance of Explosive, Implosive,
Freezing or Accelerating. The resulting GunStats retains breed, type, rarity
and profile through pickup, slot switching and dropping. Collars reflect type;
fur retains the breed's coat palette. The original three starters are retained.

October 8 catalog art updates intentionally go beyond breed reference art:
Brussels Griffon now wears a white shirt, green trousers and round spectacles
with the requested portly cartoon-sitcom feel. Otterhound is now an actual
low-poly otter with small round ears, webbed paws, whiskers and a thick tapered
tail. Both retain the same independent elemental type and attachment anchors.
