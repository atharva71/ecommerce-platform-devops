pipeline {

    agent { label 'docker' }

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT = '051987441306'
        IMAGE_NAME = 'backend-api'
        ECR_REPO = "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"
    }

    stages {
        
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Check Changed Files') {
            steps {
                script {

                    def changed = sh(
                    script: 'git diff-tree --no-commit-id --name-only -r HEAD',
                    returnStdout: true
                ).trim()

            echo changed

                    if (!changed.contains('backend-api/') &&
                    !changed.contains('frontend/')) {

                    currentBuild.result = 'SUCCESS'
                    error('Skipping application pipeline - only infrastructure files changed.')
            }
        }
    }
}

        stage('Build Backend Image') {
            steps {
                dir('backend-api') {
                    sh """
                    docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} .
                    """
                }
            }
        }

        stage('Login to Amazon ECR') {
            steps {
                sh """
                aws ecr get-login-password --region ${AWS_REGION} | \
                docker login \
                --username AWS \
                --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com
                """
            }
        }

        stage('Tag Docker Image') {
            steps {
                sh """
                docker tag ${IMAGE_NAME}:${BUILD_NUMBER} ${ECR_REPO}:${BUILD_NUMBER}
                """
            }
        }

        stage('Push Docker Image') {
            steps {
                sh """
                docker push ${ECR_REPO}:${BUILD_NUMBER}
                """
            }
        }

    }

    post {

        success {
            echo "Pipeline completed successfully."
            echo "Image pushed to: ${ECR_REPO}:${BUILD_NUMBER}"
            echo "Update k8s/backend-deployment.yaml with image tag ${BUILD_NUMBER} and push to GitHub for ArgoCD deployment."
        }

        failure {
            echo "Pipeline failed."
        }

    }
}
