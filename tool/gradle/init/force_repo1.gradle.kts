import org.gradle.api.artifacts.dsl.RepositoryHandler
import org.gradle.api.artifacts.repositories.MavenArtifactRepository
import org.gradle.kotlin.dsl.uri

fun RepositoryHandler.forceRepo1() {
    configureEach {
        if (this is MavenArtifactRepository) {
            val urlString = url.toString()
            if (urlString.contains("repo.maven.apache.org")) {
                url = uri("https://repo1.maven.org/maven2")
            }
        }
    }
}

settingsEvaluated {
    pluginManagement.repositories.forceRepo1()
    dependencyResolutionManagement?.repositories?.forceRepo1()
}

gradle.projectsLoaded {
    allprojects {
        repositories.forceRepo1()
        buildscript.repositories.forceRepo1()
    }
}
