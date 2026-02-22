// CIPHERESCROW TEAM - SAHIL SMART CONTRACT
pragma solidity ^0.8.20;

contract TrustlessEscrow {

    struct Job {
        address client;
        address freelancer;
        uint256 amount;

        bytes32 encryptedHash;
        bytes32 keyHash;              // hash of decryption key
        string fileReference;

        uint256 deadline;
        uint256 commitDeadline;

        bool funded;
        bool committed;
        bool keyRevealed;
        bool released;
    }

    uint256 public jobCounter;
    mapping(uint256 => Job) public jobs;

    event JobCreated(uint256 indexed jobId, address indexed client);
    event JobAccepted(uint256 indexed jobId, address indexed freelancer);
    event CommitSubmitted(uint256 indexed jobId);
    event KeyRevealed(uint256 indexed jobId);
    event PaymentReleased(uint256 indexed jobId);
    event JobCancelled(uint256 indexed jobId);

    modifier onlyClient(uint256 _jobId) {
        require(msg.sender == jobs[_jobId].client, "Not client");
        _;
    }

    modifier onlyFreelancer(uint256 _jobId) {
        require(msg.sender == jobs[_jobId].freelancer, "Not freelancer");
        _;
    }

    function createJob(
        uint256 _deadline,
        uint256 _commitDeadline
    ) external payable returns (uint256) {
        require(msg.value > 0, "Must fund job");
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_commitDeadline > block.timestamp, "Invalid commit deadline");
        require(_commitDeadline < _deadline, "Commit must be before final deadline");

        jobCounter++;

        jobs[jobCounter] = Job({
            client: msg.sender,
            freelancer: address(0),
            amount: msg.value,
            encryptedHash: bytes32(0),
            keyHash: bytes32(0),
            fileReference: "",
            deadline: _deadline,
            commitDeadline: _commitDeadline,
            funded: true,
            committed: false,
            keyRevealed: false,
            released: false
        });

        emit JobCreated(jobCounter, msg.sender);
        return jobCounter;
    }

    function cancelJob(uint256 _jobId)
        external
        onlyClient(_jobId)
    {
        Job storage job = jobs[_jobId];

        require(job.freelancer == address(0), "Already accepted");
        require(!job.released, "Already released");

        job.released = true;

        (bool success, ) = payable(job.client).call{value: job.amount}("");
        require(success, "Refund failed");

        emit JobCancelled(_jobId);
    }

    function acceptJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];

        require(job.funded, "Not funded");
        require(job.freelancer == address(0), "Already accepted");
        require(!job.released, "Already released");

        job.freelancer = msg.sender;

        emit JobAccepted(_jobId, msg.sender);
    }

    function submitCommit(
        uint256 _jobId,
        bytes32 _encryptedHash,
        bytes32 _keyHash,
        string memory _fileReference
    ) external onlyFreelancer(_jobId) {

        Job storage job = jobs[_jobId];

        require(block.timestamp <= job.commitDeadline, "Commit deadline passed");
        require(!job.committed, "Already committed");
        require(!job.released, "Already released");

        job.encryptedHash = _encryptedHash;
        job.keyHash = _keyHash;
        job.fileReference = _fileReference;
        job.committed = true;

        emit CommitSubmitted(_jobId);
    }

    function revealKey(uint256 _jobId, string memory _key)
        external
        onlyFreelancer(_jobId)
    {
        Job storage job = jobs[_jobId];

        require(job.committed, "No commit");
        require(!job.released, "Already released");
        require(!job.keyRevealed, "Already revealed");

        require(
            keccak256(abi.encodePacked(_key)) == job.keyHash,
            "Invalid key"
        );

        job.keyRevealed = true;

        emit KeyRevealed(_jobId);
    }

    function releasePayment(uint256 _jobId)
        external
        onlyClient(_jobId)
    {
        Job storage job = jobs[_jobId];

        require(job.committed, "No commit");
        require(job.keyRevealed, "Key not revealed");
        require(!job.released, "Already released");

        job.released = true;

        (bool success, ) = payable(job.freelancer).call{value: job.amount}("");
        require(success, "Transfer failed");

        emit PaymentReleased(_jobId);
    }

    function autoRelease(uint256 _jobId)
        external
        onlyFreelancer(_jobId)
    {
        Job storage job = jobs[_jobId];

        require(job.committed, "No commit");
        require(job.keyRevealed, "Key not revealed");
        require(block.timestamp > job.deadline, "Deadline not reached");
        require(!job.released, "Already released");

        job.released = true;

        (bool success, ) = payable(job.freelancer).call{value: job.amount}("");
        require(success, "Transfer failed");

        emit PaymentReleased(_jobId);
    }

    function refundIfNoCommit(uint256 _jobId)
        external
        onlyClient(_jobId)
    {
        Job storage job = jobs[_jobId];

        require(!job.committed, "Already committed");
        require(block.timestamp > job.commitDeadline, "Commit deadline not passed");
        require(!job.released, "Already released");

        job.released = true;

        (bool success, ) = payable(job.client).call{value: job.amount}("");
        require(success, "Refund failed");
    }

    function getJob(uint256 _jobId) external view returns (Job memory) {
        return jobs[_jobId];
    }
}