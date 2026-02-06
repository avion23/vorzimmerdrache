# N8N Workflow Management Rules

## Critical Rules to Prevent Breaking Workflows

### 1. NEVER Edit Workflows Directly in Database
- Always use n8n UI or CLI import/export
- Database edits bypass validation and cause GUI corruption

### 2. ALWAYS Validate Workflow JSON Before Import
```bash
# Check for broken connections
python3 -c "import json,sys; d=json.load(sys.stdin); nodes=[n['name'] for n in d['nodes']]; conns=[c for conn in d['connections'].values() for branch in conn.get('main',[]) for c in branch]; missing=[c['node'] for c in conns if c['node'] not in nodes]; print('Missing nodes:', missing if missing else 'None - OK')" < workflow.json
```

### 3. Use CLI for Programmatic Changes
```bash
# Export existing workflow
docker exec vorzimmerdrache-n8n-1 n8n export:workflow --id=<id> --output=/tmp/backup.json

# Edit locally, then re-import
docker exec vorzimmerdrache-n8n-1 n8n import:workflow --input=/tmp/fixed.json
```

### 4. Test Webhooks After Changes
```bash
curl -X POST https://instance1.duckdns.org/webhook/sms-response -d "From=+491711234567" -d "Body=JA"
curl -X POST https://instance1.duckdns.org/webhook/incoming-call -d "From=+491711234567" -d "To=+19135654323"
```

### 5. Backup Before Major Changes
```bash
# Backup database
ssh ralf_waldukat@instance1.duckdns.org "sudo sqlite3 /var/lib/docker/volumes/vorzimmerdrache_n8n_data/_data/database.sqlite '.backup /home/ralf_waldukat/n8n-backup-$(date +%Y%m%d-%H%M%S).sqlite'"

# Export all workflows
docker exec vorzimmerdrache-n8n-1 n8n export:workflow --all --output=/tmp/all-workflows.json
```

### 6. Version Control for Workflows
- Store workflow JSONs in git: `/Users/avion/Documents.nosync/projects/meisteranruf/backend/workflows/`
- Never commit credentials or .env files
- Tag releases before deploying

### 7. Safe Deployment Process
1. Export current workflows (backup)
2. Validate new workflow JSON locally
3. Test in n8n UI first (if possible)
4. Deploy via CLI import
5. Activate workflow via API/UI
6. Test webhooks
7. Monitor logs for 5 minutes

### 8. What Breaks Workflows (NEVER DO)
- ❌ Direct SQL updates to workflow_entity table
- ❌ Manually editing connections without updating nodes list
- ❌ Deleting nodes without removing their connections
- ❌ Creating circular connections (A→B→A)
- ❌ Using n8n 2.x with task runners on 1GB RAM (causes CPU issues)

### 9. Safe Node Operations
- ✅ Add nodes at end of workflow first
- ✅ Connect nodes only after both exist
- ✅ Use n8n UI for complex changes
- ✅ Save frequently during edits
- ✅ Test with "Execute Workflow" button

### 10. Monitoring Commands
```bash
# Check system health
ssh ralf_waldukat@instance1.duckdns.org "uptime && docker ps && docker stats --no-stream"

# Check workflow status
ssh ralf_waldukat@instance1.duckdns.org "sudo sqlite3 /var/lib/docker/volumes/vorzimmerdrache_n8n_data/_data/database.sqlite 'SELECT name, active FROM workflow_entity;'"

# Check logs
ssh ralf_waldukat@instance1.duckdns.org "docker logs vorzimmerdrache-n8n-1 --tail 50"
```

## Emergency Recovery

If workflows disappear from GUI:
1. Check for broken connections in database
2. Verify all referenced nodes exist
3. Fix connections or restore from backup
4. Restart n8n container

If CPU is high:
1. Check for task runner processes: `ps aux | grep task-runner`
2. Kill task runner: `pkill -f task-runner`
3. Consider downgrading to n8n 1.x

If credentials fail:
1. Check encryption key consistency
2. Recreate credentials via UI (never API)
3. Verify .env file matches container env vars
