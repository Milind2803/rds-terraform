pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        BACKEND_PORT = '5000'
        FRONTEND_PORT = '3000'
        DB_USER = 'admin'
        DB_PASS = 'admin123'
    }
    
    stages {

        stage('Checkout') {
            steps {
                git 'https://github.com/Milind2803/EasyCRUD-Updated-k8s.git'
            }
        }

        // 🔹 Step 1: Create MariaDB RDS
        stage('Terraform Apply') {
            steps {
                withCredentials([aws(
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    credentialsId: 'aws-cred',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {

                    sh '''
                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

                        terraform init
                        terraform apply -auto-approve
                    '''
                }
            }
        }

        // 🔹 Step 2: Get RDS Endpoint
        stage('Get RDS Endpoint') {
            steps {
                script {
                    env.RDS_ENDPOINT = sh(
                        script: "terraform output -raw rds_endpoint",
                        returnStdout: true
                    ).trim()

                    echo "RDS Endpoint: ${env.RDS_ENDPOINT}"
                }
            }
        }

        // 🔹 Step 3: Wait for DB (important)
        stage('Wait for RDS') {
            steps {
                sh 'sleep 120'
            }
        }

        // 🔹 Step 4: Install MariaDB Client
        stage('Install MariaDB Client') {
            steps {
                sh '''
                    sudo apt update
                    sudo apt install mariadb-client -y
                '''
            }
        }

        // 🔹 Step 5: Create Database student_db
        stage('Create Database') {
            steps {
                sh '''
                    mysql -h ${RDS_ENDPOINT} -u ${DB_USER} -p${DB_PASS} -e "CREATE DATABASE IF NOT EXISTS student_db;"
                '''
            }
        }

        // 🔹 Step 6: Configure Backend
        stage('Configure Backend') {
            steps {
                sh '''
                    sed -i "s|DB_HOST=.*|DB_HOST=${RDS_ENDPOINT}|" backend/src/main/resources/application.properties
                    sed -i "s|DB_NAME=.*|DB_NAME=student_db|" backend/src/main/resources/application.properties
                '''
            }
        }

        // 🔹 Step 7: Build Backend
        stage('Build Backend') {
            steps {
                sh '''
                cd EasyCRUD-Updated-k8s
                cd backend
                docker build -t my-backend ./backend
                
                '''
            }
        }

        // 🔹 Step 8: Run Backend
        stage('Run Backend') {
            steps {
                sh '''
                    docker rm -f backend || true

                    docker run -d \
                      --name backend \
                      -p ${BACKEND_PORT}:5000 \
                      my-backend
                '''
            }
        }

        // 🔹 Step 9: Configure Frontend
        stage('Configure Frontend') {
            steps {
                sh '''
                    sed -i "s|REACT_APP_API_URL=.*|REACT_APP_API_URL=http://localhost:${BACKEND_PORT}|" frontend/.env
                '''
            }
        }

        // 🔹 Step 10: Build Frontend
        stage('Build Frontend') {
            steps {
                sh '''
                cd EasyCRUD-Updated-k8s
                cd frontend
                docker build -t my-frontend ./frontend
                '''
            }
        }

        // 🔹 Step 11: Run Frontend
        stage('Run Frontend') {
            steps {
                sh '''
                    docker rm -f frontend || true

                    docker run -d \
                      --name frontend \
                      -p ${FRONTEND_PORT}:3000 \
                      my-frontend
                '''
            }
        }

        // 🔹 Step 12: Test App
        stage('Test') {
            steps {
                sh '''
                    sleep 30
                    curl http://localhost:${FRONTEND_PORT} || true
                '''
            }
        }
    }
}
