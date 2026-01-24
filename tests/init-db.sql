CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS workflow_entity (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    active BOOLEAN DEFAULT false,
    settings TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS execution_entity (
    id VARCHAR(36) PRIMARY KEY,
    workflow_id VARCHAR(36) REFERENCES workflow_entity(id) ON DELETE CASCADE,
    mode VARCHAR(50),
    status VARCHAR(50),
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    stopped_at TIMESTAMP,
    data TEXT
);

CREATE TABLE IF NOT EXISTS credentials_entity (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(100),
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO workflow_entity (id, name, active) VALUES
    ('test-workflow-1', 'Test Workflow 1', true),
    ('test-workflow-2', 'Test Workflow 2', false);

INSERT INTO credentials_entity (id, name, type) VALUES
    ('test-cred-1', 'Test Credential', 'testApi');
