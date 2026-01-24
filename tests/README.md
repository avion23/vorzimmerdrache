# Tests

## Running Tests

### Local

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage

# Run tests in CI mode
npm run test:ci
```

### Docker

Test environment uses Docker Compose for dependent services:

```bash
# Start test containers (Postgres, Redis, Waha mock, Twilio mock)
docker-compose -f docker-compose.test.yml up -d

# Wait for containers to be healthy
docker-compose -f docker-compose.test.yml ps

# Run tests with test environment variables
NODE_ENV=test npm test

# Stop and clean up containers
docker-compose -f docker-compose.test.yml down -v
```

**Required environment variables:**

```bash
# Database
POSTGRES_USER=test_user
POSTGRES_PASSWORD=test_password
POSTGRES_DB=test_db
TEST_POSTGRES_PORT=5433

# Redis
REDIS_PASSWORD=test_redis_password
TEST_REDIS_PORT=6380

# Mock services
TEST_WAHA_PORT=3001
TEST_TWILIO_PORT=8080

# Application
TWILIO_ACCOUNT_SID=AC_TEST_ACCOUNT_SID
TWILIO_AUTH_TOKEN=test_auth_token
TWILIO_PHONE_NUMBER=+1234567890
WAHA_API_URL=http://waha-mock
WAHA_API_TOKEN=test_waha_token
OPENAI_API_KEY=sk-test-key-for-mocking
GEMINI_API_KEY=test_gemini_key
GOOGLE_MAPS_API_KEY=test_maps_key
INSTALLER_PHONE_NUMBER=+49123456789
TEST_MODE=true
```

### CI

CI runs automatically on push to main/develop branches and on pull requests via GitHub Actions.

**Workflow steps:**

1. Checkout code
2. Setup Node.js (18.x, 20.x)
3. Install dependencies with `npm ci`
4. Start test containers with docker-compose
5. Wait for services to be healthy
6. Run tests with coverage: `npm run test:ci`
7. Upload coverage to Codecov
8. Teardown containers

**Coverage reporting:** Requires `CODECOV_TOKEN` secret configured in GitHub repository settings.

## Test Structure

```
tests/
├── fixtures/           # Test data and sample inputs
│   └── sample-leads.json
├── integration/        # Integration tests
│   ├── message-service.test.js
│   └── twilio-webhooks.test.js
├── mocks/              # Custom mock implementations
│   ├── twilio/
│   ├── waha/
│   ├── twilio-mock.js
│   └── waha-mock.js
├── unit/              # Unit tests
└── init-db.sql        # Test database schema and seed data
```

### Test Types

**Unit tests:** Isolated tests for individual functions/modules without external dependencies.

**Integration tests:** Tests that verify multiple components working together, using mocked external services.

**Fixtures:** Reusable test data in JSON format for consistent input across tests.

## Mocking Guidelines

### Using Nock for HTTP Requests

Mock external HTTP requests with `nock`:

```javascript
const nock = require('nock');

beforeEach(() => {
  nock.cleanAll();
});

test('should call external API', async () => {
  const scope = nock('https://api.example.com')
    .get('/endpoint')
    .reply(200, { data: 'response' });

  const result = await callExternalAPI();
  
  expect(result).toEqual({ data: 'response' });
  scope.done(); // Verify all mocked requests were called
});

afterEach(() => {
  nock.cleanAll();
});
```

### Custom Mock Services

**Twilio Mock:** Located in `tests/mocks/twilio-mock.js`

```javascript
const { TwilioMock, resetMocks } = require('../mocks/twilio-mock');

beforeEach(() => {
  twilioMock = new TwilioMock({
    accountSid: 'ACtest123',
    authToken: 'testtoken',
    phoneNumber: '+15551234567'
  });
  resetMocks();
});

test('should send SMS via mock', async () => {
  const result = await twilioMock.sendSMS('+15559876543', 'Test message');
  expect(result.success).toBe(true);
});
```

**Waha Mock:** Located in `tests/mocks/waha-mock.js`

Mock WhatsApp Business API responses for testing message service without actual WhatsApp connection.

### Mocking Best Practices

1. **Always clean up mocks** in `afterEach` to prevent test interference
2. **Use `scope.done()`** to verify all mocked requests were called
3. **Mock only what's necessary** - avoid over-mocking
4. **Return realistic responses** that match production API contracts
5. **Test both success and failure scenarios** (200, 400, 500, timeouts)
6. **Use consistent mock data** from fixtures directory
7. **Reset mock state** between tests to avoid shared state issues

### Database Mocking

For integration tests requiring database:

```javascript
beforeAll(async () => {
  // Database initialization is handled by docker-compose.test.yml
  // and init-db.sql is mounted at container startup
});

afterAll(async () => {
  // Cleanup handled by docker-compose down
});
```

## Coverage Requirements

Coverage thresholds configured in `package.json`:

```javascript
coverageThreshold: {
  global: {
    branches: 80,
    functions: 80,
    lines: 80,
    statements: 80
  }
}
```

**Requirements:**

- Minimum 80% coverage for branches, functions, lines, and statements
- Coverage is collected from `integrations/**/*.js`
- Test files (`*.test.js`, `*.example.js`) are excluded

**Viewing coverage:**

```bash
npm run test:coverage

# View HTML report
open coverage/lcov-report/index.html  # macOS
xdg-open coverage/lcov-report/index.html  # Linux
```

**Excluding code from coverage:**

```javascript
/* istanbul ignore next */
function complexEdgeCase() {
  // Code that's difficult to test
}

/* istanbul ignore file */
// Entire file excluded
```

## Troubleshooting

### Port Conflicts

**Problem:** Test containers fail to start due to port conflicts

```bash
# Check which ports are in use
lsof -i :5433  # Postgres
lsof -i :6380  # Redis
lsof -i :3001  # Waha mock
lsof -i :8080  # Twilio mock

# Solution: Change port in environment variables
export TEST_POSTGRES_PORT=5434
export TEST_REDIS_PORT=6381
```

### Container Health Failures

**Problem:** Containers not becoming healthy before tests start

```bash
# Check container status
docker-compose -f docker-compose.test.yml ps

# View container logs
docker-compose -f docker-compose.test.yml logs postgres-test
docker-compose -f docker-compose.test.yml logs redis-test
docker-compose -f docker-compose.test.yml logs waha-mock
docker-compose -f docker-compose.test.yml logs twilio-mock

# Restart unhealthy containers
docker-compose -f docker-compose.test.yml restart postgres-test
```

### Timeout Errors

**Problem:** Tests timeout waiting for services

```bash
# Increase Jest timeout in package.json
"jest": {
  "testTimeout": 30000
}

# Or per test:
test('slow test', async () => {
  // ...
}, 30000);
```

### Nock Issues

**Problem:** Nock mocks not matching or cleaning up properly

```javascript
// Enable Nock debugging
nock.restore();
nock.recorder.rec();

// Check active mocks
console.log(nock.activeMocks());

// Ensure cleanup
afterEach(() => {
  nock.cleanAll();
});
```

### Database Connection Failures

**Problem:** Cannot connect to test database

```bash
# Verify Postgres container is running
docker ps | grep postgres-test

# Test connection manually
docker exec -it postgres-test psql -U test_user -d test_db -c "SELECT 1;"

# Reinitialize database
docker-compose -f docker-compose.test.yml down -v
docker-compose -f docker-compose.test.yml up -d
```

### Coverage Below Threshold

**Problem:** Coverage requirements not met

```bash
# Generate detailed coverage report
npm run test:coverage

# View uncovered lines
cat coverage/lcov.info | grep "DA:" | grep ",0" | head -20

# Temporarily reduce threshold for debugging
# Edit package.json coverageThreshold values
```

### Mock Service Not Responding

**Problem:** Waha or Twilio mock returning errors

```bash
# Check mock service logs
docker-compose -f docker-compose.test.yml logs waha-mock
docker-compose -f docker-compose.test.yml logs twilio-mock

# Test mock service directly
curl http://localhost:3001/health  # Waha
curl http://localhost:8080/health  # Twilio

# Verify mock configuration files exist
ls -la tests/mocks/waha/
ls -la tests/mocks/twilio/
```

### Test Flakiness

**Problem:** Tests pass/fail intermittently

```bash
# Run tests multiple times to identify flaky tests
npm test -- --repeat=5

# Increase timeout for specific tests
jest.setTimeout(10000);

# Add retries for specific tests (experimental)
jest.retryTimes(3);
```

### CI-Specific Issues

**Problem:** Tests pass locally but fail in CI

```bash
# Check CI environment variables differ from local
# Node version may differ
# Timing issues more likely in CI

# Run locally with CI configuration
NODE_ENV=test npm run test:ci

# Match CI Node version
nvm install 18  # or 20
```

### Cleanup Issues

**Problem:** Resources not cleaned up between tests

```bash
# Force remove all containers and volumes
docker-compose -f docker-compose.test.yml down -v --remove-orphans

# Remove unused Docker resources
docker system prune -f

# Restart Docker daemon (if needed)
sudo systemctl restart docker  # Linux
# macOS: Restart Docker Desktop
```

## Adding New Tests

1. **Unit test:** Add to `tests/unit/` if testing isolated functions
2. **Integration test:** Add to `tests/integration/` if testing multiple components
3. **Fixtures:** Add test data to `tests/fixtures/` for reuse
4. **Custom mocks:** Add to `tests/mocks/` for new service mocking

**Naming convention:** `*.test.js` for Jest test files

```javascript
// tests/integration/new-feature.test.js
const nock = require('nock');
const FeatureService = require('../../integrations/new-feature/service');

describe('New Feature', () => {
  let service;

  beforeEach(() => {
    nock.cleanAll();
    service = new FeatureService();
  });

  afterEach(() => {
    nock.cleanAll();
  });

  test('should do something', async () => {
    // Arrange
    const expected = 'result';
    
    // Act
    const actual = await service.doSomething();
    
    // Assert
    expect(actual).toBe(expected);
  });
});
```
