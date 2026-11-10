"""Read-only structural validation of the public handover (no network or secrets)."""
from pathlib import Path
import csv,hashlib,json,re,subprocess,sys
root=Path(__file__).resolve().parents[1]
docs=root/'docs/handover'
manifest=json.loads((docs/'project-manifest.json').read_text())
errors=[]
for name in manifest['required_chapters']:
 path=docs/name
 if not path.is_file() or path.stat().st_size<1000:errors.append('Missing or insubstantial chapter: '+name)
for path in docs.glob('*.md'):
 for target in re.findall(r'\]\(([^)]+)\)',path.read_text()):
  target=target.split('#',1)[0]
  if not target or '://' in target or target.startswith('mailto:'):continue
  if not (path.parent/target).resolve().exists():errors.append('Broken link: '+path.name+' -> '+target)
rows=list(csv.DictReader((docs/'feature-traceability.csv').open()))
if len(rows)!=manifest['feature_summary']['features'] or len({r['id'] for r in rows})!=len(rows):errors.append('Feature count/identity mismatch')
for row in rows:
 if any(not value for value in row.values()):errors.append('Empty feature field: '+row['id'])
 for value in row['source_paths'].split(';'):
  if not (root/value).is_file():errors.append('Invalid source path: '+value)
for migration in manifest['migrations']:
 path=root/migration['file']
 if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=migration['sha256']:errors.append('Migration mismatch: '+migration['file'])
for path in subprocess.check_output(['git','ls-files'],cwd=root,text=True).splitlines():
 parts=Path(path).parts
 if any(p in {'private','.local-private','handover-private','credentials','secrets','agent-state','private-exports','local-exports'} for p in parts):errors.append('Tracked private path: '+path)
 if path.endswith(('.key','.pem','.db','.sqlite','.sqlite3','.key.enc')):errors.append('Tracked secret/runtime extension: '+path)
if errors:
 print('\n'.join(errors));sys.exit(1)
print(json.dumps({'chapters':len(manifest['required_chapters']),'features':len(rows),'migrations':len(manifest['migrations']),'errors':0}))
