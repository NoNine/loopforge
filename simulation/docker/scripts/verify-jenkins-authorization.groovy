import hudson.model.Item
import hudson.security.GlobalMatrixAuthorizationStrategy
import jenkins.model.Jenkins

def strategy = Jenkins.get().authorizationStrategy
assert strategy instanceof GlobalMatrixAuthorizationStrategy

def grants = strategy.grantedPermissionEntries
def hasSid = { permission, sid ->
    grants[permission] != null && grants[permission].any { it.sid == sid }
}

assert hasSid(Jenkins.ADMINISTER, 'jenkins-admin')
assert hasSid(Jenkins.READ, 'authenticated')
assert hasSid(Item.READ, 'authenticated')
assert hasSid(Item.BUILD, 'authenticated')
println('jenkins-authorization=ready strategy=global-matrix admin=jenkins-admin authenticated=read,job-read,job-build')
