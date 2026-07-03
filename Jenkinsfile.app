pipeline {

    agent { label 'docker' }

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT = '051987441306'
        
        BACKEND_IMAGE = 'backend-api'
        FRONTEND_IMAGE = 'frontend'

        BACKEND_ECR = "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BACKEND_IMAGE}"
        SKIP_PIPELINE = 'false'
        FRONTEND_ECR = "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FRONTEND_IMAGE}"
    }

    stages {
        
        stage('Checkout')
	{ 
	   steps {
		   checkout scm
		}
	} 
        
        stage('Check Commit Message') {
            steps {
                script {
                    def commitMsg = sh(
                        script: "git log -1 --pretty=%B",
                        returnStdout: true
                    ).trim()

                    echo "Latest Commit: ${commitMsg}"

                    if (commitMsg.contains("[skip-ci]")) {
                        echo "GitOps commit detected. Skipping Application Pipeline."
                        env.SKIP_PIPELINE = "true"
                        currentBuild.result = "NOT_BUILT"
                    }
                }
            }
        }
    		}  
	}	        
        
        
        stage('Check Changed Files') {
            when {
                expression { env.SKIP_PIPELINE != "true" }
            }
            steps {
                script {
                    def changed = sh(
                        script: 'git diff-tree --no-commit-id --name-only -r HEAD',
                        returnStdout: true
                    ).trim()

                    echo changed

                    if (!changed.contains('backend-api/') &&
                        !changed.contains('frontend/')) {
                        echo "Infrastructure-only commit. Skipping Application Pipeline."
                        env.SKIP_PIPELINE = "true"
                        currentBuild.result = "NOT_BUILT"
                    }
                }
            }
        }
}
        stage('Login to Amazon ECR') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                sh """
                aws ecr get-login-password --region ${AWS_REGION} | \
                docker login \
                --username AWS \
                --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com
                """
            }
        }
        
        stage('Build Backend Image') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                dir('backend-api') {
                    sh """
                    docker build -t ${BACKEND_IMAGE}:${BUILD_NUMBER} .
                    """
                }
            }
        }

        stage('Build Frontend Image') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                dir('frontend') {
                    sh """
                    docker build -t ${FRONTEND_IMAGE}:${BUILD_NUMBER} .
                    """
                }
            }
        }

        
        stage('Tag Backend Image') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                sh """
                docker tag ${BACKEND_IMAGE}:${BUILD_NUMBER} \
                ${BACKEND_ECR}:${BUILD_NUMBER}
                """
            }
        }

        stage('Tag Frontend Image') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                sh """
                docker tag ${FRONTEND_IMAGE}:${BUILD_NUMBER} \
                ${FRONTEND_ECR}:${BUILD_NUMBER}
                """
            }
        }

        stage('Push Backend Image') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                sh """
                docker push ${BACKEND_ECR}:${BUILD_NUMBER}
                """
            }
        }

        stage('Push Frontend Image') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {
                sh """
                docker push ${FRONTEND_ECR}:${BUILD_NUMBER}
                """
            }
        }

        stage('Update Kubernetes Manifests') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {

                sh """
                sed -i 's|image: .*|image: ${BACKEND_ECR}:${BUILD_NUMBER}|' \
                k8s/backend-deployment.yaml

                sed -i 's|image: .*|image: ${FRONTEND_ECR}:${BUILD_NUMBER}|' \
                k8s/frontend-deployment.yaml
                """
            }
        }
        
        stage('Commit and Push GitOps Changes') {
            when {
                expression { env.SKIP_PIPELINE != \"true\" }
            }
            steps {

                withCredentials([
                usernamePassword(
                credentialsId: 'github_pat',
                usernameVariable: 'GITHUB_USER',
                passwordVariable: 'GITHUB_PAT'
            )
        ]) {

                sh """
                git config user.email "jenkins@local"
                git config user.name "Jenkins"

                git add k8s/backend-deployment.yaml
                git add k8s/frontend-deployment.yaml

                git commit -m "[skip-ci] Update backend/frontend images ${BUILD_NUMBER}" || true

                git remote set-url origin https://${GITHUB_USER}:${GITHUB_PAT}@github.com/atharva71/ecommerce-platform-devops.git

                git push origin HEAD:main
                """
            }
        }
    }
}
    post {

        success {
            echo "Pipeline completed successfully."
            echo "Backend Image : ${BACKEND_ECR}:${BUILD_NUMBER}"
            echo "Frontend Image: ${FRONTEND_ECR}:${BUILD_NUMBER}"
            echo "Kubernetes manifests updated and pushed to GitHub."
        }

        failure {
            echo "Pipeline failed."
        }

        
    }
}
